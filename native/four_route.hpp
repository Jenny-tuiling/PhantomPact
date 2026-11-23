#pragma once
#include <windows.h>
#include <cstdio>
#include <string>
#include <sstream>
#include <charconv>
#include <share.h>

namespace fourroute {
struct Binding { unsigned long long player[4]{}; int device[4]{1,2,3,4}; ULONGLONG updated=0; int count=4; };
inline Binding binding;
inline FILETIME last_write{};
inline SRWLOCK lock=SRWLOCK_INIT;
inline volatile LONG devices[16]{}, targets[4]{}, rejected=0;
inline void stats(const std::wstring& path) {
    static ULONGLONG last=0;
    if(GetTickCount64()-last<1000) return;
    last=GetTickCount64();
    FILE* f=nullptr;
    if(_wfopen_s(&f,path.c_str(),L"w")==0 && f) {
        for(int i=0;i<16;i++) if(devices[i]) fprintf(f,"device %d events %ld\n",i,devices[i]);
        for(int i=0;i<4;i++) fprintf(f,"player %d events %ld\n",i+1,targets[i]);
        fprintf(f,"unassigned %ld\n",rejected); fclose(f);
    }
}
// The Lua writer truncates then publishes a small five-line record. Never let
// a short read combine parsed rows with Binding's default device assignments.
inline bool parse(const std::string& text,Binding& output) {
    if(text.empty() || text.size()>512)return false;
    std::istringstream input(text);Binding next;std::string line,extra;
    for(unsigned i=0;i<4;i++) {
        if(!std::getline(input,line))return false;
        std::istringstream row(line);std::string address,device;
        if(!(row>>address>>device) || (row>>extra))return false;
        if(address.empty() || address.find_first_not_of("0123456789")!=std::string::npos)return false;
        const auto converted=std::from_chars(address.data(),address.data()+address.size(),next.player[i]);
        if(converted.ec!=std::errc{} || converted.ptr!=address.data()+address.size())return false;
        if(device=="-1")next.device[i]=-1;
        else if(device.size()==1 && device[0]>='0' && device[0]<='4')next.device[i]=device[0]-'0';
        else return false;
    }
    if(!std::getline(input,line))return false;
    std::istringstream countLine(line);std::string count;
    if(!(countLine>>count) || (countLine>>extra) || count.size()!=1 || count[0]<'0' || count[0]>'4')return false;
    if(std::getline(input,line))return false; // exactly five lines; no partial/extra records
    next.count=count[0]-'0';
    bool allEmpty=true;
    for(unsigned i=0;i<4;i++)allEmpty=allEmpty && next.player[i]==0 && next.device[i]==-1;
    if(!allEmpty) {
        if(next.count==0)return false;
        for(int i=0;i<4;i++) {
            if(i>=next.count){if(next.player[i]!=0 || next.device[i]!=-1)return false;continue;}
            if(!next.player[i])return false;
            for(int j=0;j<i;j++) {
                if(next.player[i]==next.player[j])return false;
                if(next.device[i]>=0 && next.device[i]==next.device[j])return false;
            }
        }
    }
    output=next;return true;
}
inline void read(const std::wstring& path) {
    WIN32_FILE_ATTRIBUTE_DATA info{};
    if(!GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&info) ||
        CompareFileTime(&last_write,&info.ftLastWriteTime)==0)return;
    // Share access with Lua's writer; malformed/torn records are rejected below.
    FILE* f=_wfsopen(path.c_str(),L"rb",_SH_DENYNO);if(!f)return;
    char bytes[513];const auto size=fread(bytes,1,sizeof(bytes),f);const bool failed=ferror(f)!=0;fclose(f);
    if(failed || size==sizeof(bytes))return;
    Binding next;if(!parse(std::string(bytes,size),next))return;
    WIN32_FILE_ATTRIBUTE_DATA after{};
    if(!GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&after) ||
        CompareFileTime(&info.ftLastWriteTime,&after.ftLastWriteTime)!=0 ||
        info.nFileSizeHigh!=after.nFileSizeHigh || info.nFileSizeLow!=after.nFileSizeLow)return;
    // Missing/invalid records leave the old updated time untouched, so existing
    // 1.5-second routing/watchdog expiry still neutralizes stale input naturally.
    next.updated=next.count>=2?GetTickCount64():0; // complete count0/1 explicitly disables routing
    AcquireSRWLockExclusive(&lock); binding=next; ReleaseSRWLockExclusive(&lock);
    last_write=after.ftLastWriteTime;
}
using Input=ULONG_PTR(*)(void*,BYTE*,void*,void*);
// Offsets reported by this installation's UE4SS dump; require their readback
// to match the four controller IDs before temporarily routing an event.
inline bool dispatch(Input real,void* self,BYTE* args,void* a3,void* a4,ULONG_PTR* result) {
    Binding b;
    AcquireSRWLockShared(&lock); b=binding; ReleaseSRWLockShared(&lock);
    if(!b.updated || GetTickCount64()-b.updated>1500) return false;
    int ids[4]{}, users[4]{}; int changed=0;
    __try {
        const int device=*reinterpret_cast<int*>(args+0x0C);
        if(device>=0 && device<16) InterlockedIncrement(&devices[device]);
        int target=device==0?0:-1;
        for(int i=0;i<b.count;i++) if(b.device[i]>=0 && b.device[i]==device) target=i;
        for(int i=0;i<b.count;i++) {
            if(!b.player[i]) return false;
            auto p=reinterpret_cast<BYTE*>(b.player[i]);
            ids[i]=*reinterpret_cast<int*>(p+0xE0);
            users[i]=*reinterpret_cast<int*>(p+0x104);
            if(ids[i]!=i) return false;
        }
        // An unassigned/disconnected gamepad cannot take over player 1.
        if(target<0) { InterlockedIncrement(&rejected); *result=1; return true; }
        InterlockedIncrement(&targets[target]);
        for(int i=0;i<b.count;i++) {
            auto p=reinterpret_cast<BYTE*>(b.player[i]);
            *reinterpret_cast<int*>(p+0xE0)=i==target?0:16+i;
            *reinterpret_cast<int*>(p+0x104)=i==target?0:16+i;
            changed=i+1;
        }
        *result=real(self,args,a3,a4);
    } __finally {
        for(int i=0;i<changed;i++) {
            auto p=reinterpret_cast<BYTE*>(b.player[i]);
            *reinterpret_cast<int*>(p+0xE0)=ids[i];
            *reinterpret_cast<int*>(p+0x104)=users[i];
        }
    }
    return true;
}
}
