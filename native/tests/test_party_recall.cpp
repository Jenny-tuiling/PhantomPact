#define NOMINMAX
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
using namespace partyinput;
static unsigned checks=0;
#define CHECK(x) do{++checks;if(!(x))throw std::runtime_error(#x);}while(0)
fourroute::Binding route;
XINPUT_GAMEPAD run(unsigned device,WORD buttons,ULONGLONG now,BYTE lt=0,BYTE rt=0,bool focus=true,DWORD result=ERROR_SUCCESS){
    route.updated=now;XINPUT_STATE s{};s.Gamepad.wButtons=buttons;s.Gamepad.bLeftTrigger=lt;s.Gamepad.bRightTrigger=rt;
    transform(device,result,&s,route,focus,now);return s.Gamepad;
}
void reset(int count=4){
    recovery={};ai=partyai::Control{99};locked=false;keyboard={};route={};route.count=count;
    for(int i=0;i<4;i++){route.player[i]=i<count?1000+i:0;route.device[i]=i<count?i+1:-1;owner[i]=-1;chords[i]={};sequence[i]=0;deliveredPad[i]={};packet[i]=0;}
}
void arm(){for(unsigned i=0;i<4;i++)run(i,0,100);}
int main(){
    constexpr WORD R3=XINPUT_GAMEPAD_RIGHT_THUMB,L3=XINPUT_GAMEPAD_LEFT_THUMB;
    for(int count=2;count<=4;count++){
        reset(count);arm();
        auto s=run(0,R3|XINPUT_GAMEPAD_A,200,255);CHECK(s.wButtons==XINPUT_GAMEPAD_A&&s.bLeftTrigger==0);
        run(0,R3,3199,255);CHECK(recovery.recall==0);run(0,R3,3200,255);CHECK(recovery.recall==1);
        CHECK(!locked&&recovery.safe==0&&sequence[1]==0&&sequence[2]==0&&sequence[3]==0);
        run(0,R3,9999,255);CHECK(recovery.recall==1);
        run(0,0,10000,80);run(0,R3,10100,255);run(0,R3,15000,255);CHECK(recovery.recall==1);
        run(0,0,15100);run(0,R3,15200,255);run(0,R3,18200,255);CHECK(recovery.recall==2);
        for(unsigned i=1;i<unsigned(count);i++){run(i,R3,200,255);run(i,R3,9999,255);CHECK(recovery.recall==2);}
    }
    // Device 4 is the host, not player 4; keyboard host has no pad recall.
    reset();std::swap(route.device[0],route.device[3]);arm();run(3,R3,200,255);run(3,R3,3200,255);CHECK(recovery.recall==1);
    reset();route.device[0]=0;route.device[1]=1;route.device[2]=2;route.device[3]=3;arm();
    run(0,R3,200,255);run(0,R3,9999,255);CHECK(recovery.recall==0);
    // Startup held, focus, disconnect and route identity changes require release.
    reset();run(0,R3,100,255);run(0,R3,9999,255);CHECK(recovery.recall==0);
    for(int why=0;why<4;why++){
        reset();arm();run(0,R3,200,255);
        if(why==0)run(0,R3,1000,255,0,false);
        if(why==1)run(0,R3,1000,255,0,true,ERROR_DEVICE_NOT_CONNECTED);
        if(why==2){route.player[0]=2222;run(0,R3,1000,255);}
        if(why==3){route.device[1]=route.device[0];run(0,R3,1000,255);route.device[1]=2;}
        run(0,R3,9999,255);CHECK(recovery.recall==0);
        run(0,0,10000);run(0,R3,10100,255);run(0,R3,13100,255);CHECK(recovery.recall==1);
    }
    // Press threshold / release hysteresis, no accidental camera/safe/lock.
    reset();arm();run(0,R3,200,127);run(0,R3,9999,127);CHECK(recovery.recall==0);
    run(0,R3,10000,128);run(0,R3,12999,80);CHECK(recovery.recall==0);run(0,R3,13000,80);CHECK(recovery.recall==1);
    for(WORD extra:{WORD(L3),WORD(XINPUT_GAMEPAD_DPAD_DOWN),WORD(XINPUT_GAMEPAD_DPAD_UP)}){
        reset();arm();run(0,R3|extra,200,255);run(0,R3|extra,9999,255);
        CHECK(recovery.recall==0&&recovery.safe==0&&recovery.camera[0]==0&&!locked);
        run(0,R3,10000,255);run(0,R3,15000,255);CHECK(recovery.recall==0);
    }
    reset();arm();run(0,R3,200,255,255);run(0,R3,9999,255,255);CHECK(!locked&&!recovery.recall);
    run(0,R3,10000,255,80);run(0,R3,15000,255,80);CHECK(!recovery.recall);
    // Inactive LT noise above release prevents changing recall into a lock.
    reset();arm();run(0,R3,200,255);run(0,R3,3200,255);run(0,0,3300,80);
    run(0,L3,3400,80,255);run(0,L3,7000,80,255);CHECK(!locked&&recovery.recall==1);
    // Normal R3 or LT still reaches gameplay when not used as a combo.
    reset();arm();run(0,R3,200);CHECK(run(0,R3,400).wButtons==R3);run(0,0,500);
    CHECK(run(0,0,600,255).bLeftTrigger==255);
    // Host lock never disables raw recall, and hook/poll share one latch.
    reset();arm();locked=true;XINPUT_GAMEPAD p{};p.wButtons=R3;p.bLeftTrigger=255;bool fired=false;
    recovery.sampleRecall(0,true,p,200,&fired);CHECK(!fired);run(0,R3,3200,255);
    recovery.sampleRecall(0,true,p,3200,&fired);CHECK(!fired&&recovery.recall==1&&locked);
    session=99;installed=true;sequence[1]=7;sequence[2]=8;sequence[3]=9;
    CHECK(control_status(4)=="99 1 7 8 9 1 4 1\n");
    // Actual monotonic 3-second boundary using synthetic input only.
    reset();auto start=GetTickCount64();run(0,0,start);start=GetTickCount64();run(0,R3,start,255);
    ULONGLONG elapsed=0;
    while(!recovery.recall){auto now=GetTickCount64();run(0,R3,now,255);CHECK(now-start<3500);if(now-start<3000)CHECK(!recovery.recall);Sleep(5);elapsed=now-start;}
    CHECK(elapsed>=3000&&elapsed<3500);
    std::cout<<"Party recall: "<<checks<<" checks passed; real hold="<<elapsed<<"ms; no game/device input\n";
}
