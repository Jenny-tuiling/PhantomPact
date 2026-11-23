#pragma once
#include <windows.h>
#include <Xinput.h>
#include <delayimp.h>
#include <cmath>
#include <algorithm>
#include "four_route.hpp"
#include "party_ai.hpp"
#include "party_recovery_input.hpp"
#include "recovery_keyboard.hpp"

namespace partyinput {
using Get=DWORD(WINAPI*)(DWORD,XINPUT_STATE*);
using Set=DWORD(WINAPI*)(DWORD,XINPUT_VIBRATION*);
inline Get raw=nullptr; inline Set vibrate=nullptr;
inline SRWLOCK mutex=SRWLOCK_INIT;
struct Calibration { int center[4]{}; int dead[2]{}; };
struct Chord { ULONGLONG first=0, both=0; bool consumed=false, fired=false, delivered=false; WORD last=0; };
inline Calibration calibration[4]; inline Chord chords[4], keyboard;
inline bool locked=false, installed=false;
inline unsigned sequence[4]{};
inline ULONGLONG rumbleEnd[4]{}, session=GetTickCount64();
inline partyai::Control ai{session};
inline partyrecovery::Control recovery;
inline LONG recoveryFocusEpoch=0;
inline int owner[4]{-1,-1,-1,-1};
inline XINPUT_GAMEPAD deliveredPad[4]{};inline DWORD packet[4]{};
inline bool foreground() { DWORD pid=0;GetWindowThreadProcessId(GetForegroundWindow(),&pid);return pid==GetCurrentProcessId(); }
inline void sync_recovery(const fourroute::Binding& binding,bool active,ULONGLONG now){
    const LONG epoch=InterlockedCompareExchange(&recoverykeys::focusEpoch,0,0);
    if(epoch!=recoveryFocusEpoch){recovery.bound=false;recoveryFocusEpoch=epoch;}
    recovery.sync(binding,active,now);
}
inline bool held(Chord& c,bool a,bool b,ULONGLONG now,ULONGLONG duration=2000) {
    if(!a && !b) {c={};return false;}
    if(!c.first)c.first=now;
    if(a && b) {
        c.consumed=true;
        if(!c.both)c.both=now;
        if(!c.fired && now-c.both>=duration){c.fired=true;return true;}
    } else c.both=0;
    return false;
}
inline SHORT centered(SHORT value,int center) {
    double d=double(value)-center;
    if(d==0)return 0;
    double span=d>=0?32767.0-center:32768.0+center;
    return static_cast<SHORT>(std::clamp(d/span*32767.0,-32767.0,32767.0));
}
inline void stick(SHORT& x,SHORT& y,int cx,int cy,int dead) {
    if(!cx && !cy && !dead)return;
    double a=centered(x,cx),b=centered(y,cy),length=std::sqrt(a*a+b*b);
    if(length<=dead){x=y=0;return;}
    double gain=std::min(32767.0,(length-dead)*32767.0/(32767-dead))/length;
    x=static_cast<SHORT>(a*gain);y=static_cast<SHORT>(b*gain);
}
inline void bind_ai(const fourroute::Binding& binding,ULONGLONG now) {
    const bool live=binding.updated && now-binding.updated<1500;
    bool unroute=binding.count>=2 && binding.count<=4;
    for(unsigned i=0;i<4;i++)unroute=unroute && binding.player[i]==0 && binding.device[i]==-1;
    for(unsigned slot=1;slot<4;slot++) {
        int matches=0;
        for(int i=0;i<binding.count && i<4;i++)if(binding.device[i]==binding.device[slot])++matches;
        const bool included=binding.count>=2 && binding.count<=4 && slot<static_cast<unsigned>(binding.count);
        const bool transient=included && (unroute || (!live && matches==1 && binding.device[slot]>=1 && binding.device[slot]<=4));
        ai.bind(slot,binding.device[slot],binding.player[slot],live && included && matches==1,now,transient);
    }
}
// Caller holds mutex. Kept separate from the actual hook for deterministic tests.
inline DWORD transform(DWORD index,DWORD result,XINPUT_STATE* state,const fourroute::Binding& binding,bool active,ULONGLONG now) {
    if(index>=4 || !state)return result;
    ai.focus(active,now);
    bind_ai(binding,now);ai.watchdog(now);
    sync_recovery(binding,active,now);
    int player=-1;
    if(binding.updated && now-binding.updated<1500)
        for(int i=0;i<binding.count;i++)if(binding.device[i]==int(index)+1)player=i;
    if(result!=ERROR_SUCCESS || player<0 || !active) {
        recovery.sampleLock(index,false,{},now);
        recovery.sampleRecall(index,false,{},now);
        recovery.sample(index,false,{},false,now);
        if(player>0 && result!=ERROR_SUCCESS)ai.stop(player,partyai::Disconnected,now);
        // Release the last delivered state once before reporting device removal or a lost route.
        // A Lua-side watchdog may already have disabled the mode, so use delivered state here.
        const XINPUT_GAMEPAD neutral{};
        if((player>0 || owner[index]>0) && memcmp(&deliveredPad[index],&neutral,sizeof(neutral))) {
            state->Gamepad={};deliveredPad[index]={};state->dwPacketNumber=++packet[index];
            chords[index]={};owner[index]=player;return ERROR_SUCCESS;
        }
        chords[index]={};owner[index]=player;return result;
    }
    if(owner[index]!=player){chords[index]={};owner[index]=player;}
    auto& p=state->Gamepad;auto& c=chords[index];
    const bool aiSwitched=ai.raw(player,p,now,!locked);
    const bool aiChord=player>0 && ai.mode[player].hold.consumed;
    bool hostLockSwitched=false;
    const bool hostLockChord=recovery.sampleLock(index,true,p,now,&hostLockSwitched);
    if(hostLockSwitched)locked=!locked;
    bool recallSwitched=false;
    const bool recallChord=recovery.sampleRecall(index,true,p,now,&recallSwitched);
    bool recoverySwitched=false;
    const WORD recoveryMask=recovery.sample(index,true,p,aiChord || hostLockChord || recallChord || (player>0 && (p.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)!=0),now,&recoverySwitched);
    if(aiChord || hostLockChord || recallChord || recoveryMask)c={}; // Never let a recovery click leak into regroup or ordinary input.
    WORD thumb=p.wButtons&0xC0;
    WORD tap=!thumb && c.first && !c.consumed && !c.delivered?c.last:0;
    bool oldSwitched=false;
    if(!aiChord && !hostLockChord && !recallChord && !recoveryMask && held(c,(p.wButtons&0x40)!=0,(p.wButtons&0x80)!=0,now,3000) && player>0) {
        sequence[player]++;
        oldSwitched=true;
    }
    if((aiSwitched || hostLockSwitched || recallSwitched || oldSwitched || recoverySwitched) && vibrate){XINPUT_VIBRATION v{18000,18000};vibrate(index,&v);rumbleEnd[index]=now+220;}
    // A 180 ms chord window avoids sending sprint/lock-on when pressed together.
    if(c.consumed || (c.first && now-c.first<180))p.wButtons&=~WORD(0xC0);
    else if(thumb)c.delivered=true;
    c.last=thumb;
    p.wButtons|=tap; // preserve a quick single-stick click after the chord window
    const auto& k=calibration[index];
    stick(p.sThumbLX,p.sThumbLY,k.center[0],k.center[1],k.dead[0]);
    stick(p.sThumbRX,p.sThumbRY,k.center[2],k.center[3],k.dead[1]);
    if(aiChord || hostLockChord){p.wButtons&=~WORD(XINPUT_GAMEPAD_LEFT_THUMB);p.bRightTrigger=0;}
    if(recallChord){p.wButtons&=~WORD(XINPUT_GAMEPAD_RIGHT_THUMB);p.bLeftTrigger=0;}
    if(player>0 && ai.mode[player].enabled)p=ai.output(player,now);
    if(player>0 && ai.mode[player].handoffPending){p={};ai.mode[player].handoffPending=false;}
    p.wButtons&=~recoveryMask; // Also consume conflicting buttons in an AI-generated frame.
    if(locked && player>0)p={}; // raw chord above still allows guest rescue
    if(!packet[index] || memcmp(&p,&deliveredPad[index],sizeof(p))) {
        deliveredPad[index]=p;++packet[index];
    }
    state->dwPacketNumber=packet[index]; // calibration/lock changes count even at rest
    return result;
}
inline DWORD WINAPI get(DWORD index,XINPUT_STATE* state) {
    DWORD result=raw(index,state);
    if(index>=4)return result;
    fourroute::Binding binding;
    AcquireSRWLockShared(&fourroute::lock);binding=fourroute::binding;ReleaseSRWLockShared(&fourroute::lock);
    AcquireSRWLockExclusive(&mutex);
    result=transform(index,result,state,binding,foreground(),GetTickCount64());
    ReleaseSRWLockExclusive(&mutex);
    return result;
}
inline bool install() {
    if(installed)return true;
    HMODULE dll=LoadLibraryW(L"xinput1_4.dll");
    raw=reinterpret_cast<Get>(GetProcAddress(dll,"XInputGetState"));
    vibrate=reinterpret_cast<Set>(GetProcAddress(dll,"XInputSetState"));
    if(!raw)return false;
    auto base=reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(base);
    auto nt=reinterpret_cast<IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
    auto entry=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT];
    if(!entry.VirtualAddress)return false;
    auto desc=reinterpret_cast<ImgDelayDescr*>(base+entry.VirtualAddress);
    for(;desc->rvaDLLName;desc++) {
        if(!(desc->grAttrs&dlattrRva) || _stricmp(reinterpret_cast<char*>(base+desc->rvaDLLName),"xinput1_4.dll"))continue;
        auto names=reinterpret_cast<IMAGE_THUNK_DATA64*>(base+desc->rvaINT);
        auto addresses=reinterpret_cast<IMAGE_THUNK_DATA64*>(base+desc->rvaIAT);
        for(size_t i=0;names[i].u1.AddressOfData;i++) {
            if(IMAGE_SNAP_BY_ORDINAL64(names[i].u1.Ordinal))continue;
            auto name=reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(base+names[i].u1.AddressOfData);
            if(strcmp(reinterpret_cast<char*>(name->Name),"XInputGetState"))continue;
            DWORD old=0;
            if(!VirtualProtect(&addresses[i],sizeof(addresses[i]),PAGE_READWRITE,&old))return false;
            InterlockedExchangePointer(reinterpret_cast<void* volatile*>(&addresses[i].u1.Function),reinterpret_cast<void*>(&get));
            DWORD ignored;VirtualProtect(&addresses[i],sizeof(addresses[i]),old,&ignored);
            installed=true;return true;
        }
    }
    return false;
}
inline std::string control_status(int count) {
    // Append-only protocol extension: the existing seven fields retain their meaning.
    return std::to_string(session)+" "+std::to_string(locked)+" "+std::to_string(sequence[1])+" "+std::to_string(sequence[2])+" "+std::to_string(sequence[3])+" "+std::to_string(installed)+" "+std::to_string(count)+" "+std::to_string(recovery.recall)+"\n";
}
inline void poll(const std::wstring& dir) {
    install();
    const bool keyboardReady=recoverykeys::ensure();
    fourroute::Binding binding;
    AcquireSRWLockShared(&fourroute::lock);binding=fourroute::binding;ReleaseSRWLockShared(&fourroute::lock);
    partyai::Packet aiPacket;const bool hasAi=partyai::read(dir+L"\\party_ai_input.txt",aiPacket);
    Calibration next[4]{};FILE* f=nullptr;
    if(_wfopen_s(&f,(dir+L"\\four_calibration.txt").c_str(),L"r")==0 && f) {
        bool ok=true;
        for(auto& k:next) {
            if(fscanf_s(f,"%d %d %d %d %d %d",&k.center[0],&k.center[1],&k.center[2],&k.center[3],&k.dead[0],&k.dead[1])!=6)ok=false;
            for(int c:k.center)if(c < -32768 || c > 32767)ok=false;
            for(int d:k.dead)if(d<0 || d>9000)ok=false;
        }
        fclose(f);
        if(ok){AcquireSRWLockExclusive(&mutex);std::copy(std::begin(next),std::end(next),calibration);ReleaseSRWLockExclusive(&mutex);}
    }
    AcquireSRWLockExclusive(&mutex);
    auto now=GetTickCount64();
    bool active=foreground();
    ai.focus(active,now);
    sync_recovery(binding,active && installed,now); // Do not queue commands behind a failed hook.
    bind_ai(binding,now);
    if(hasAi)ai.accept(aiPacket,now);
    for(unsigned uiSlot=2;uiSlot<=4;uiSlot++){
        FILE* uiFile=nullptr;std::string uiText;
        auto uiPath=dir+L"\\party_ai_set_"+std::to_wstring(uiSlot)+L".txt";
        if(_wfopen_s(&uiFile,uiPath.c_str(),L"rb")==0 && uiFile){char buf[257];auto n=fread(buf,1,sizeof(buf),uiFile);fclose(uiFile);if(n<=256)uiText.assign(buf,n);}
        if(!uiText.empty())ai.request(uiText,now,installed && !locked && uiSlot<=static_cast<unsigned>(binding.count));
    }
    ai.watchdog(now);
    for(unsigned slot=1;slot<4;slot++) {
        if(active && ai.mode[slot].device>0 && raw) {
            XINPUT_STATE physical{};
            const auto index=ai.mode[slot].device-1;
            if(raw(index,&physical)!=ERROR_SUCCESS)ai.stop(slot,partyai::Disconnected,now);
            else if(ai.raw(slot,physical.Gamepad,now,!locked) && vibrate) {
                XINPUT_VIBRATION v{18000,18000};vibrate(index,&v);rumbleEnd[index]=now+220;
            }
        }
    }
    // Poll every physical device, including P1, so recovery still works when
    // the game stops asking XInput during a stuck UI. Shared Hold state makes
    // this and the XInput hook a single source of commands.
    for(unsigned index=0;index<4;index++){
        XINPUT_STATE physical{};const int player=recovery.seat(index);
        const bool connected=active && player>=0 && raw && raw(index,&physical)==ERROR_SUCCESS;
        const bool priority=player>0 && ai.mode[player].hold.consumed;
        bool lockFired=false;
        const bool hostPriority=recovery.sampleLock(index,connected,physical.Gamepad,now,&lockFired);
        if(lockFired)locked=!locked;
        bool recallFired=false;
        const bool recallPriority=recovery.sampleRecall(index,connected,physical.Gamepad,now,&recallFired);
        bool fired=false;
        recovery.sample(index,connected,physical.Gamepad,priority || hostPriority || recallPriority || (player>0 && (physical.Gamepad.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)!=0),now,&fired);
        if((fired || lockFired || recallFired) && vibrate){XINPUT_VIBRATION v{18000,18000};vibrate(index,&v);rumbleEnd[index]=now+220;}
    }
    bool control=(GetAsyncKeyState(VK_LCONTROL)&0x8000)!=0;
    bool shift=(GetAsyncKeyState(VK_LSHIFT)&0x8000)!=0;
    bool z=(GetAsyncKeyState('Z')&0x8000)!=0;
    bool alt=(GetAsyncKeyState(VK_LMENU)&0x8000)!=0;
    bool r=(GetAsyncKeyState('R')&0x8000)!=0;
    bool fkey=(GetAsyncKeyState('F')&0x8000)!=0;
    InterlockedExchange(&recoverykeys::routeActive,recovery.bound);
    if(keyboardReady)recovery.keys(control,alt,r,fkey,shift,now,(!r||recoverykeys::captured('R')) && (!fkey||recoverykeys::captured('F')));
    else recovery.keyboard={}; // Never partially enable an unfiltered shortcut.
    if(active && control && shift) {if(held(keyboard,z,z,now))locked=!locked;} else keyboard={};
    for(int i=0;i<4;i++)if(rumbleEnd[i] && now>=rumbleEnd[i]){
        XINPUT_VIBRATION v{};if(vibrate)vibrate(i,&v);rumbleEnd[i]=0;
    }
    AcquireSRWLockShared(&fourroute::lock);int count=fourroute::binding.count;ReleaseSRWLockShared(&fourroute::lock);
    std::string status=control_status(count);
    std::string aiStatus=ai.status(installed);
    std::string recoveryStatus=recovery.status(session,installed);
    ReleaseSRWLockExclusive(&mutex);
    localio::write_atomic(dir+L"\\four_actions.txt",status);
    localio::write_atomic(dir+L"\\party_ai_status.txt",aiStatus);
    localio::write_atomic(dir+L"\\recovery_actions.txt",recoveryStatus);
    localio::write_atomic(dir+L"\\recovery_input_status.txt",recoverykeys::status(installed));
}
}



