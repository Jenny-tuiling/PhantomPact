// Real elapsed-clock test of production input code. Does not read or send any
// keyboard/controller input; synthetic states enter transform() in this process.
#define NOMINMAX
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
using namespace partyinput;
fourroute::Binding binding;
unsigned long long packetSequence=0;
void heartbeat(ULONGLONG now) {
    partyai::Packet p;p.session=ai.session;p.sequence=++packetSequence;
    for(unsigned i=0;i<3;++i){p.frame[i].slot=i+2;p.frame[i].epoch=ai.mode[i+1].epoch;p.frame[i].allow=true;}
    ai.accept(p,now);
}
XINPUT_STATE run(unsigned index,XINPUT_GAMEPAD pad,ULONGLONG now) {
    binding.updated=now;XINPUT_STATE state{};state.Gamepad=pad;
    assert(transform(index,ERROR_SUCCESS,&state,binding,true,now)==ERROR_SUCCESS);
    return state;
}
void reset() {
    ai=partyai::Control{22};recovery={};locked=false;packetSequence=0;
    for(auto& c:chords)c={};for(auto& s:sequence)s=0;
    for(auto& p:deliveredPad)p={};for(auto& p:packet)p=0;
    binding.count=4;for(int i=0;i<4;i++){binding.player[i]=1000+i;binding.device[i]=i+1;owner[i]=-1;}
}
int main() {
    reset();auto start=GetTickCount64();run(1,{},start);
    XINPUT_GAMEPAD aiChord{};aiChord.wButtons=XINPUT_GAMEPAD_LEFT_THUMB;aiChord.bRightTrigger=255;
    start=GetTickCount64();run(1,aiChord,start);ULONGLONG aiElapsed=0;
    while(true){auto now=GetTickCount64();heartbeat(now);run(1,aiChord,now);
        if(ai.mode[1].enabled){aiElapsed=now-start;break;}
        assert(now-start<4500);Sleep(5);
    }
    assert(aiElapsed>=4000 && aiElapsed<4500);
    reset();start=GetTickCount64();run(0,{},start);run(2,{},start);
    XINPUT_GAMEPAD sticks{};sticks.wButtons=XINPUT_GAMEPAD_LEFT_THUMB|XINPUT_GAMEPAD_RIGHT_THUMB;
    start=GetTickCount64();run(0,aiChord,start);run(2,sticks,start);
    partyinput::Chord keys;held(keys,true,true,start);ULONGLONG host=0,guest=0,keyboardMs=0;
    while(!host || !guest || !keyboardMs){auto now=GetTickCount64();run(0,aiChord,now);run(2,sticks,now);
        if(locked && !host)host=now-start;
        if(sequence[2] && !guest)guest=now-start;
        if(held(keys,true,true,now) && !keyboardMs)keyboardMs=now-start;
        if(now-start<3000){assert(!locked);assert(sequence[2]==0);}
        assert(now-start<3500);Sleep(5);
    }
    assert(host>=3000 && host<3500);assert(guest>=3000 && guest<3500);
    assert(keyboardMs>=2000 && keyboardMs<2500);
    auto later=GetTickCount64()+10000;run(0,aiChord,later);run(2,sticks,later);
    assert(locked && sequence[2]==1);
    std::cout<<"PASS real elapsed ms: AI="<<aiElapsed<<" host_lock="<<host<<" guest_regroup="<<guest<<" keyboard_lock="<<keyboardMs<<"\n";
}
