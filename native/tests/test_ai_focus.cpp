#define NOMINMAX
#include <cstring>
#include <iostream>
#include <stdexcept>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
static int checks=0;
#define CHECK(x) do { ++checks; if(!(x))throw std::runtime_error(#x); } while(0)
using namespace partyinput;
bool zero(const XINPUT_GAMEPAD& p){XINPUT_GAMEPAD n{};return std::memcmp(&p,&n,sizeof(n))==0;}
partyai::Packet frame(unsigned long long n){
    partyai::Packet p;p.session=ai.session;p.sequence=n;
    for(unsigned i=0;i<3;i++)p.frame[i]={i+2,ai.mode[i+1].epoch,true,{XINPUT_GAMEPAD_A,0,0,12000,0,0,0}};
    return p;
}
int main(){
 for(int count=2;count<=4;count++)for(bool mixed:{false,true}){
    ai=partyai::Control{123};locked=false;recovery={};
    fourroute::Binding b;b.count=count;b.updated=100;
    const int devices[4]={mixed?0:1,4,3,2};
    for(int i=0;i<4;i++){b.player[i]=i<count?1000+i:0;b.device[i]=i<count?devices[i]:-1;}
    bind_ai(b,100);for(int i=1;i<count;i++)ai.mode[i].enabled=true;
    unsigned long long seq=1;ai.accept(frame(seq++),100);
    for(int i=1;i<count;i++)CHECK(!zero(ai.output(i,100)));
    auto old=frame(seq++);XINPUT_STATE state{};
    transform(3,ERROR_SUCCESS,&state,b,false,101);
    for(int i=1;i<count;i++){CHECK(ai.mode[i].enabled);CHECK(zero(ai.output(i,101)));CHECK(ai.mode[i].reason==partyai::FocusLost);}
    const auto epoch=ai.mode[1].epoch;
    for(int i=0;i<50;i++){ai.focus(false,102+i);CHECK(!ai.accept(frame(seq++),102+i));CHECK(ai.mode[1].epoch==epoch);}
    CHECK(!ai.raw(1,{},170));auto background=frame(seq++);
    b.updated=200;transform(3,ERROR_SUCCESS,&state,b,true,200);
    CHECK(ai.mode[1].enabled && zero(ai.output(1,200)));CHECK(ai.mode[1].epoch>epoch);
    ai.accept(old,201);ai.accept(background,202);CHECK(zero(ai.output(1,202)));
    ai.accept(frame(seq++),203);CHECK(!zero(ai.output(1,203)));
    // Loading route disappearance and rebuilt controllers preserve the mode.
    auto empty=b;empty.updated=204;for(int i=0;i<4;i++){empty.player[i]=0;empty.device[i]=-1;}
    bind_ai(empty,204);for(int i=1;i<count;i++){CHECK(ai.mode[i].enabled);CHECK(zero(ai.output(i,204)));}
    b.updated=205;for(int i=0;i<count;i++)b.player[i]+=10000;bind_ai(b,205);
    ai.accept(frame(seq++),206);for(int i=1;i<count;i++)CHECK(ai.mode[i].enabled&&!zero(ai.output(i,206)));
    // Host recall is an independent command and must not clear any guest mode.
    if(!mixed){
      XINPUT_STATE host{};b.updated=300;transform(0,ERROR_SUCCESS,&host,b,true,300);
      host.Gamepad.wButtons=XINPUT_GAMEPAD_RIGHT_THUMB;host.Gamepad.bLeftTrigger=255;
      b.updated=301;transform(0,ERROR_SUCCESS,&host,b,true,301);
      host.Gamepad.wButtons=XINPUT_GAMEPAD_RIGHT_THUMB;host.Gamepad.bLeftTrigger=255;
      b.updated=3301;transform(0,ERROR_SUCCESS,&host,b,true,3301);
      CHECK(recovery.recall==1);for(int i=1;i<count;i++)CHECK(ai.mode[i].enabled);
    }
    // Actual physical removal still returns the affected player to manual.
    b.updated=4000;transform(3,ERROR_DEVICE_NOT_CONNECTED,&state,b,true,4000);CHECK(ai.mode[1].enabled && zero(ai.output(1,4000)));
    CHECK(!ai.mode[0].enabled);
 }
 std::cout<<"ai_focus: "<<checks<<" checks passed\n";
}
