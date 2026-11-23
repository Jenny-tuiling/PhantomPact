// Synthetic production input tests: no OS keyboard/controller input is sent.
#define NOMINMAX
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
using namespace partyinput;
fourroute::Binding binding;
XINPUT_GAMEPAD pad(WORD buttons){XINPUT_GAMEPAD p{};p.wButtons=buttons;return p;}
void reset(){
    ai=partyai::Control{22};recovery={};locked=false;keyboard={};
    for(auto& c:chords)c={};for(auto& s:sequence)s=0;
    for(auto& p:deliveredPad)p={};for(auto& p:packet)p=0;
    binding={};binding.count=4;
    for(int i=0;i<4;i++){binding.player[i]=1000+i;binding.device[i]=i+1;owner[i]=-1;}
}
XINPUT_GAMEPAD run(unsigned index,WORD buttons,ULONGLONG now,bool focus=true,DWORD result=ERROR_SUCCESS,BYTE rt=0){
    binding.updated=now;XINPUT_STATE state{};state.Gamepad=pad(buttons);state.Gamepad.bRightTrigger=rt;
    transform(index,result,&state,binding,focus,now);return state.Gamepad;
}
void arm(ULONGLONG now=100){for(unsigned i=0;i<4;i++)run(i,0,now);}
int main(){
    constexpr WORD camera=partyrecovery::CAMERA_BUTTONS,safe=partyrecovery::SAFE_BUTTONS;
    reset();arm();
    for(unsigned i=0;i<4;i++){
        auto visible=run(i,camera|XINPUT_GAMEPAD_A,200);
        assert(visible.wButtons==XINPUT_GAMEPAD_A);
        run(i,camera,2199);assert(recovery.camera[i]==0);
        run(i,camera,2200);assert(recovery.camera[i]==1);
        run(i,camera,9999);assert(recovery.camera[i]==1);
    }
    assert(!locked && sequence[1]==0 && sequence[2]==0 && sequence[3]==0);
    assert(recovery.status(22,true)=="PBZRECINPUT1 22 1 1 1 1 0 1\n");

    reset();arm();run(0,safe,200);run(0,safe,3199);assert(recovery.safe==0);
    run(0,safe,3200);assert(recovery.safe==1);run(0,safe,9999);assert(recovery.safe==1);
    for(unsigned i=1;i<4;i++){run(i,safe,200);run(i,safe,9999);}
    assert(recovery.safe==1 && !locked);

    // Startup, partial releases, direction switches and simultaneous directions.
    reset();run(0,camera,100);run(0,camera,9999);assert(recovery.camera[0]==0);
    run(0,0,10000);run(0,camera,10100);run(0,XINPUT_GAMEPAD_RIGHT_THUMB,11100);
    run(0,camera,11200);run(0,camera,20000);assert(recovery.camera[0]==0);
    run(0,0,20100);run(0,camera,20200);run(0,safe,21000);run(0,safe,30000);
    assert(recovery.safe==0 && recovery.camera[0]==0);
    run(0,0,30100);run(0,camera|safe,30200);run(0,camera,40000);assert(recovery.camera[0]==0);
    run(0,0,40100);run(0,camera,40200);run(0,camera,42200);assert(recovery.camera[0]==1);
    run(0,0,42300);run(0,camera,42400);run(0,camera,44400);assert(recovery.camera[0]==2);

    // Focus loss / disconnect / mapping changes cannot finish a held command.
    for(int interruption=0;interruption<4;interruption++){
        reset();arm();run(1,camera,200);
        if(interruption==0)run(1,camera,1000,false);
        if(interruption==1)run(1,camera,1000,true,ERROR_DEVICE_NOT_CONNECTED);
        if(interruption==2){std::swap(binding.device[1],binding.device[2]);run(1,camera,1000);}
        if(interruption==3){binding.player[1]=2222;run(1,camera,1000);}
        run(1,camera,9999);for(auto n:recovery.camera)assert(n==0);
        run(1,0,10000);run(1,camera,10100);run(1,camera,12100);
        assert(recovery.camera[interruption==2?2:1]==1);
    }
    // Mapping 1,3,2,4 is a device mapping, never a player-number assumption.
    reset();arm();run(0,camera,200);InterlockedIncrement(&recoverykeys::focusEpoch);
    run(0,camera,9999);assert(recovery.camera[0]==0); // focus loss+regain between poll samples
    reset();binding.device[1]=3;binding.device[2]=2;arm();
    run(2,camera,200);run(2,camera,2200);
    assert(recovery.camera[1]==1 && recovery.camera[2]==0);
    // Duplicated devices and a stale route are rejected, including keyboard.
    reset();binding.device[2]=2;arm();run(1,camera,200);run(1,camera,9999);
    assert(recovery.camera[1]==0 && !recovery.bound);
    reset();arm();binding.updated=100;recovery.sync(binding,true,2000);
    recovery.sample(0,true,pad(camera),false,9999);assert(recovery.camera[0]==0);

    // A single R3 click / Dpad button keeps its existing game behavior.
    reset();arm();run(0,XINPUT_GAMEPAD_RIGHT_THUMB,200);
    assert(run(0,XINPUT_GAMEPAD_RIGHT_THUMB,400).wButtons==XINPUT_GAMEPAD_RIGHT_THUMB);
    run(0,0,500);assert(run(0,XINPUT_GAMEPAD_DPAD_DOWN,600).wButtons==XINPUT_GAMEPAD_DPAD_DOWN);
    // Recovery cancels pending L3+R3 rather than accidentally locking/regrouping.
    reset();arm();run(0,camera|XINPUT_GAMEPAD_LEFT_THUMB,200);
    run(0,camera|XINPUT_GAMEPAD_LEFT_THUMB,9999);assert(!locked && recovery.camera[0]==0);
    run(0,camera,10000);run(0,camera,20000);assert(!locked && recovery.camera[0]==0);
    // Host sticks now request safe return; guest sticks still regroup at 3s.
    reset();arm();for(unsigned i=0;i<4;i++)run(i,0xC0,200);
    for(unsigned i=0;i<4;i++)run(i,0xC0,3199);assert(!locked && !sequence[1]);
    for(unsigned i=0;i<4;i++)run(i,0xC0,3200);
    assert(!locked && recovery.safe==1 && sequence[1]==1 && sequence[2]==1 && sequence[3]==1);
    locked=true;
    // Locking ordinary controls never prevents a recovery command.
    run(1,0,3300);run(1,camera,3400);assert(run(1,camera,5400).wButtons==0);
    assert(recovery.camera[1]==1);
    // Poll + hook samples use the same latch and cannot double-count.
    reset();arm();recovery.sample(2,true,pad(camera),false,200);
    run(2,camera,2200);recovery.sample(2,true,pad(camera),false,2200);
    assert(recovery.camera[2]==1);

    // P1 L3+RT now locks at exactly 3s and never requests safe return or AI.
    reset();arm();
    auto lockRun=[](ULONGLONG now,BYTE rt=255,WORD buttons=XINPUT_GAMEPAD_LEFT_THUMB){return run(0,buttons,now,true,ERROR_SUCCESS,rt);};
    assert(lockRun(200).bRightTrigger==0);lockRun(3199);assert(!locked);
    lockRun(3200);assert(locked && recovery.safe==0 && !ai.mode[0].enabled);
    lockRun(9999);assert(locked); // one-shot while held
    lockRun(10000,32);lockRun(10100);lockRun(14000);assert(locked); // partial release cannot rearm
    lockRun(14100,0,0);lockRun(14200);lockRun(17200);assert(!locked);
    // P1 trigger hysteresis, unrelated inputs, and obsolete R3+Up.
    reset();arm();run(0,XINPUT_GAMEPAD_RIGHT_THUMB|XINPUT_GAMEPAD_DPAD_UP,200);
    run(0,XINPUT_GAMEPAD_RIGHT_THUMB|XINPUT_GAMEPAD_DPAD_UP,9999);assert(!recovery.safe && !locked);
    run(0,0,10000);lockRun(10100,127);lockRun(15000,127);assert(!locked);
    lockRun(15100,128);lockRun(18099,80);assert(!locked);lockRun(18100,80);assert(locked);
    // Mixing host safe and lock cannot trigger either until complete release.
    reset();arm();lockRun(200,255,0xC0);lockRun(9999,255,0xC0);assert(!locked && !recovery.safe);
    lockRun(10000,0,0xC0);lockRun(15000,0,0xC0);assert(!locked && !recovery.safe);
    run(0,0,15100);run(0,safe,15200);run(0,safe,18200);assert(recovery.safe==1 && !locked);
    // A missed/failing game XInput read can still trigger host lock in poll.
    reset();arm();bool fired=false;
    XINPUT_GAMEPAD hostPad=pad(XINPUT_GAMEPAD_LEFT_THUMB);hostPad.bRightTrigger=255;
    recovery.sampleLock(0,true,hostPad,200,&fired);assert(!fired);
    recovery.sampleLock(0,true,hostPad,3200,&fired);assert(fired);if(fired)locked=!locked;
    run(0,XINPUT_GAMEPAD_LEFT_THUMB,3200,true,ERROR_SUCCESS,255);assert(locked);
    // Host lock timing is dropped on focus loss, disconnect and rebind.
    for(int why=0;why<3;why++){
        reset();arm();lockRun(200);
        if(why==0)run(0,XINPUT_GAMEPAD_LEFT_THUMB,1000,false,ERROR_SUCCESS,255);
        if(why==1)run(0,XINPUT_GAMEPAD_LEFT_THUMB,1000,true,ERROR_DEVICE_NOT_CONNECTED,255);
        if(why==2){binding.player[0]=2222;lockRun(1000);}
        lockRun(9999);assert(!locked);lockRun(10000,0,0);lockRun(10100);lockRun(13100);assert(locked);
    }

    // Keyboard boundaries, modifiers, one-shot and focus reset.
    reset();arm();recovery.keys(false,false,false,false,false,100);
    recovery.keys(true,true,true,false,false,200);
    recovery.keys(true,true,true,false,false,2199);assert(recovery.camera[0]==0);
    recovery.keys(true,true,true,false,false,2200);assert(recovery.camera[0]==1);
    recovery.keys(true,true,true,false,false,9999);assert(recovery.camera[0]==1);
    recovery.keys(true,true,false,false,false,10000);
    recovery.keys(true,true,false,true,false,10100);recovery.keys(true,true,false,true,false,20000);
    assert(recovery.safe==0); // modifiers also must be released to rearm
    recovery.keys(false,false,false,false,false,20100);recovery.keys(true,true,false,true,false,20200);
    recovery.keys(true,true,false,true,false,23199);assert(recovery.safe==0);
    recovery.keys(true,true,false,true,false,23200);assert(recovery.safe==1);
    recovery.sync(binding,false,23300);binding.updated=23400;recovery.sync(binding,true,23400);
    recovery.keys(true,true,false,true,false,23400);recovery.keys(true,true,false,true,false,30000);assert(recovery.safe==1);
    for(int modifier=0;modifier<3;modifier++){
        recovery.keys(false,false,false,false,false,30100);
        recovery.keys(modifier!=0,modifier!=1,true,false,modifier==2,30200);
        recovery.keys(modifier!=0,modifier!=1,true,false,modifier==2,40000);assert(recovery.camera[0]==1);
    }
    recovery.keys(false,false,false,false,false,40100);
    recovery.keys(true,true,true,true,false,40200);recovery.keys(true,true,true,false,false,50000);
    assert(recovery.camera[0]==1 && recovery.safe==1);
    // A poll preceding WM_KEYDOWN waits for capture instead of firing an
    // unfiltered shortcut or poisoning the next legitimate captured event.
    recovery.keys(false,false,false,false,false,50100);
    recovery.keys(true,true,true,false,false,50200,false);
    recovery.keys(true,true,true,false,false,60000,false);assert(recovery.camera[0]==1);
    recovery.keys(true,true,true,false,false,60100,true);
    recovery.keys(true,true,true,false,false,62099,true);assert(recovery.camera[0]==1);
    recovery.keys(true,true,true,false,false,62100,true);assert(recovery.camera[0]==2);

    // Real monotonic elapsed time: P1 safe + P2 camera + keyboard camera.
    reset();auto start=GetTickCount64();arm(start);recovery.keys(false,false,false,false,false,start);
    start=GetTickCount64();run(0,safe,start);run(1,camera,start);recovery.keys(true,true,true,false,false,start);
    ULONGLONG safeElapsed=0,cameraElapsed=0,keyboardElapsed=0;
    while(!safeElapsed || !cameraElapsed || !keyboardElapsed){
        const auto now=GetTickCount64();run(0,safe,now);run(1,camera,now);recovery.keys(true,true,true,false,false,now);
        if(recovery.camera[1]&&!cameraElapsed)cameraElapsed=now-start;
        if(recovery.camera[0]&&!keyboardElapsed)keyboardElapsed=now-start;
        if(recovery.safe&&!safeElapsed)safeElapsed=now-start;
        if(now-start<2000)assert(!recovery.camera[0]&&!recovery.camera[1]);
        if(now-start<3000)assert(!recovery.safe);
        assert(now-start<3500);Sleep(5);
    }
    assert(cameraElapsed>=2000 && cameraElapsed<2500 && keyboardElapsed>=2000 && keyboardElapsed<2500);
    assert(safeElapsed>=3000 && safeElapsed<3500);
    std::cout<<"PASS recovery: four seats, 2s camera, 3s P1 safe, keyboard, consume, one-shot, partial release, conflict, focus, disconnect, binding identity, stale/duplicate route, old chords, poll/hook dedup; real elapsed ms camera="<<cameraElapsed<<" safe="<<safeElapsed<<" keyboard="<<keyboardElapsed<<"\n";
}
