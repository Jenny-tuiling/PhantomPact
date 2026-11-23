#define NOMINMAX
#include <cstring>
#include <iostream>
#include <fstream>
#include <stdexcept>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
static unsigned checks=0,cases=0;
#define CHECK(x) do{++checks;if(!(x))throw std::runtime_error(#x);}while(0)
const wchar_t* PATH=L"reader-fixture.txt";
void writeText(const std::string& text){
 {std::ofstream f("reader-fixture.txt",std::ios::binary|std::ios::trunc);f<<text;}
 static ULONGLONG stamp=0;FILETIME ft;GetSystemTimeAsFileTime(&ft);ULARGE_INTEGER u;u.LowPart=ft.dwLowDateTime;u.HighPart=ft.dwHighDateTime;
 stamp=std::max(stamp+10,u.QuadPart);u.QuadPart=stamp;ft.dwLowDateTime=u.LowPart;ft.dwHighDateTime=u.HighPart;
 HANDLE h=CreateFileW(PATH,FILE_WRITE_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);
 CHECK(h!=INVALID_HANDLE_VALUE);CHECK(SetFileTime(h,nullptr,nullptr,&ft)!=0);CloseHandle(h);
}
std::string record(const int* map,int count=4,bool empty=false){
 std::string s;for(int i=0;i<4;i++)s+=(empty||i>=count)?"0 -1\n":std::to_string(1000+i)+" "+std::to_string(map[i])+"\n";
 return s+std::to_string(count)+"\n";
}
bool same(const fourroute::Binding&a,const fourroute::Binding&b){
 if(a.count!=b.count||a.updated!=b.updated)return false;
 for(int i=0;i<4;i++)if(a.player[i]!=b.player[i]||a.device[i]!=b.device[i])return false;
 return true;
}
void start(const int* map,int count=4){
 partyinput::ai=partyai::Control{99};fourroute::last_write={};
 writeText(record(map,count));fourroute::read(PATH);CHECK(fourroute::binding.updated!=0);
 partyinput::bind_ai(fourroute::binding,GetTickCount64());
 for(int i=1;i<count;i++)partyinput::ai.mode[i].enabled=true;
}
void unchangedAfter(const std::string& text){
 const auto good=fourroute::binding;const auto oldTime=fourroute::last_write;
 writeText(text);fourroute::read(PATH);CHECK(same(good,fourroute::binding));
 CHECK(CompareFileTime(&oldTime,&fourroute::last_write)==0);
 partyinput::bind_ai(fourroute::binding,GetTickCount64());
 for(int i=1;i<good.count;i++)CHECK(partyinput::ai.mode[i].enabled);
}
int main(){
 const int maps[][4]={{1,2,3,4},{4,2,1,3},{0,1,2,3},{3,4,2,1}};
 for(const auto& map:maps)for(int count=2;count<=4;count++){
  cases++;start(map,count);const auto active=record(map,count),blank=record(map,count,true);
  // Every missing/partial byte, including in an address or device token, keeps
  // the last complete route and intent. Only a complete count may be accepted.
  for(const auto* source:{&active,&blank})for(size_t cut=0;cut<source->size()-1;cut++){
   unchangedAfter(source->substr(0,cut));
  }
  // A full unroute is still applied immediately and suspends, never cancels AI.
  writeText(blank);fourroute::read(PATH);CHECK(fourroute::binding.updated!=0);
  partyinput::bind_ai(fourroute::binding,GetTickCount64());
  for(int i=1;i<count;i++){CHECK(partyinput::ai.mode[i].enabled);CHECK(partyinput::ai.mode[i].identity==0);}
  writeText(active);fourroute::read(PATH);partyinput::bind_ai(fourroute::binding,GetTickCount64());
  for(int i=1;i<count;i++)CHECK(partyinput::ai.mode[i].enabled);
 }
 // The parser does not mutate its caller on malformed full records either.
 const std::string bad[]={
  "1000 1\n1001 2\n1002 3\n1003 4\n", // missing count, legacy 4-line prefix
  "1000 1\n1001 2\n1002 3\n1003 4\n5\n",
  "1000 1\n1001 2\n1002 3\n1003 4\n-1\n",
  "1000 1\n1001 2\n1002 3\n1003 4\n4 extra\n",
  "1000 1\n1001 2\n1002 3\n1003 4\n4\nextra\n",
  "1000 1\n1001 2\n1002 3\n1003 4\n4\n\n",
  "1000 1\n1001 2\n1002 3\n1003 5\n4\n",
  "1000 1\n1001 2\n1002 3\n1003 -2\n4\n",
  "-1000 1\n1001 2\n1002 3\n1003 4\n4\n",
  "18446744073709551616 1\n1001 2\n1002 3\n1003 4\n4\n",
  "1000 1 extra\n1001 2\n1002 3\n1003 4\n4\n",
  "1000 1\n1001 2\n1002 2\n1003 4\n4\n", // duplicate physical device
  "1000 0\n1001 0\n1002 2\n1003 4\n4\n", // duplicate keyboard identity
  "1000 1\n1000 2\n1002 3\n1003 4\n4\n", // duplicate LocalPlayer
  "1000 1\n0 -1\n1002 3\n1003 4\n4\n", // incomplete active player set
  "1000 1\n1001 2\n1002 3\n0 -1\n2\n", // unexpected inactive seat
  "1000 1\n1001 2\n1002 3\n1003 4\n1\n",
  "1000 1\n1001 2\n1002 3\n1003 4\n0\n",
  std::string(513,'x')};
 for(const auto& text:bad){cases++;start(maps[0]);unchangedAfter(text);}
 cases++;start(maps[0]);auto good=fourroute::binding;
 unchangedAfter("0 -1\n0 -1\n");
 // Timestamp is not refreshed: normal expiry neutralizes AI without clearing intent.
 CHECK(fourroute::binding.updated==good.updated);
 partyinput::bind_ai(fourroute::binding,good.updated+1601);
 for(int i=1;i<4;i++){CHECK(partyinput::ai.mode[i].enabled);CHECK(partyinput::ai.mode[i].identity==0);CHECK(!partyinput::ai.mode[i].allow);}
 // Genuine full manual unassignment, count reduction, focus loss and unplug retain their old meaning.
 cases++;start(maps[0]);const int unassigned[]={1,-1,3,4};writeText(record(unassigned));fourroute::read(PATH);partyinput::bind_ai(fourroute::binding,GetTickCount64());
 CHECK(partyinput::ai.mode[1].enabled && !partyinput::ai.mode[1].allow);CHECK(partyinput::ai.mode[2].enabled&&partyinput::ai.mode[3].enabled);
 cases++;start(maps[0]);writeText(record(maps[0],2));fourroute::read(PATH);partyinput::bind_ai(fourroute::binding,GetTickCount64());
 CHECK(partyinput::ai.mode[1].enabled);CHECK(partyinput::ai.mode[2].enabled&&partyinput::ai.mode[3].enabled);CHECK(!partyinput::ai.mode[2].allow&&!partyinput::ai.mode[3].allow);
 for(int count=0;count<=1;count++)for(bool blank:{false,true}){
  if(count==0&&!blank)continue;
  cases++;start(maps[0]);writeText(record(maps[0],count,blank));fourroute::read(PATH);
  CHECK(fourroute::binding.count==count&&fourroute::binding.updated==0);
  partyinput::bind_ai(fourroute::binding,GetTickCount64());for(int i=1;i<4;i++)CHECK(partyinput::ai.mode[i].enabled && !partyinput::ai.mode[i].allow);
 }
 for(int reason:{partyai::Disconnected,partyai::FocusLost}){
  cases++;start(maps[0]);partyinput::ai.stop(1,reason,GetTickCount64());CHECK(partyinput::ai.mode[1].enabled && !partyinput::ai.mode[1].allow);
 }
 cases++;start(maps[0]);good=fourroute::binding;fourroute::read(L"missing-no-such-fixture.txt");CHECK(same(good,fourroute::binding));
 // CRLF and a complete final count without newline remain supported.
 cases++;fourroute::Binding parsed;CHECK(fourroute::parse("1000 1\r\n1001 2\r\n0 -1\r\n0 -1\r\n2\r\n",parsed));
 CHECK(parsed.count==2);CHECK(fourroute::parse("0 -1\n0 -1\n0 -1\n0 -1\n4",parsed));
 std::cout<<"route_reader: "<<cases<<" cases / "<<checks<<" checks passed; actual Windows file reader + AI bind\n";
}
