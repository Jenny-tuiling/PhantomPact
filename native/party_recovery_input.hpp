#pragma once
#include <windows.h>
#include <Xinput.h>
#include <string>
#include "four_route.hpp"

// Input-only recovery commands. The game-thread Lua adapter owns whether a
// camera reset / return is currently safe; this module never moves a Pawn.
namespace partyrecovery {
constexpr ULONGLONG CAMERA_MS=2000, SAFE_MS=3000;
constexpr WORD CAMERA_BUTTONS=XINPUT_GAMEPAD_RIGHT_THUMB|XINPUT_GAMEPAD_DPAD_DOWN;
constexpr WORD SAFE_BUTTONS=XINPUT_GAMEPAD_LEFT_THUMB|XINPUT_GAMEPAD_RIGHT_THUMB;
constexpr BYTE LOCK_TRIGGER_ON=128, LOCK_TRIGGER_OFF=32;

struct Hold {
    bool armed=false, consumed=false, timing=false, fired=false, blocked=false;
    int action=0; ULONGLONG start=0;
    // allReleased is deliberately the entire chord family. Sliding from one
    // direction/key to the other cannot rearm, nor can reconnecting while held.
    int sample(bool allReleased,int requested,bool conflict,ULONGLONG now) {
        if(allReleased){*this={};armed=true;return 0;}
        if(conflict){blocked=true;timing=false;}
        if(requested){consumed=true;if(!action)action=requested;}
        if(!armed || blocked || fired)return 0;
        if(!requested || (action && requested!=action)){
            if(timing){blocked=true;timing=false;}return 0;
        }
        if(!timing){start=now;timing=true;}
        if(now<start){blocked=true;timing=false;return 0;}
        if(now-start>=(action==1?CAMERA_MS:SAFE_MS)){fired=true;return action;}
        return 0;
    }
};

struct Control {
    Hold pads[4]{},keyboard{},hostLock{},hostRecall{};
    bool hostTrigger=false,recallTrigger=false;
    unsigned camera[4]{},safe=0,recall=0; // uint32 counters, matching the Lua parsers
    fourroute::Binding identity{};
    bool bound=false;
    bool sync(const fourroute::Binding& b,bool active,ULONGLONG now) {
        bool valid=active && b.updated && now>=b.updated && now-b.updated<1500 && b.count>=2 && b.count<=4;
        if(valid)for(int i=0;i<b.count;i++){
            if(!b.player[i])valid=false;
            for(int j=0;j<i;j++)if(b.player[i]==b.player[j] || (b.device[i]>0 && b.device[i]==b.device[j]))valid=false;
        }
        bool changed=!bound || identity.count!=b.count;
        for(int i=0;i<4;i++)if(identity.player[i]!=b.player[i] || identity.device[i]!=b.device[i])changed=true;
        if(!valid || changed){for(auto& p:pads)p={};keyboard={};hostLock={};hostTrigger=false;hostRecall={};recallTrigger=false;}
        identity=b;bound=valid;return valid;
    }
    int seat(unsigned index)const{
        if(!bound || index>=4)return -1;
        for(int i=0;i<identity.count;i++)if(identity.device[i]==static_cast<int>(index)+1)return i;
        return -1;
    }
    // Host-only L3+RT uses the same 3s one-shot/release latch as safe return.
    // The shared Control instance is sampled by both hook and background poll.
    bool sampleLock(unsigned index,bool connected,const XINPUT_GAMEPAD& p,ULONGLONG now,bool* fired=nullptr) {
        if(fired)*fired=false;
        if(seat(index)!=0)return false;
        if(!connected){hostLock={};hostTrigger=false;return false;}
        if(p.bRightTrigger>=LOCK_TRIGGER_ON)hostTrigger=true;
        else if(p.bRightTrigger<=LOCK_TRIGGER_OFF)hostTrigger=false;
        const bool left=(p.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)!=0;
        const bool other=(p.wButtons&(XINPUT_GAMEPAD_RIGHT_THUMB|XINPUT_GAMEPAD_DPAD_DOWN|XINPUT_GAMEPAD_DPAD_UP))!=0||p.bLeftTrigger>LOCK_TRIGGER_OFF;
        const bool released=!left&&!hostTrigger&&!other;
        const int event=hostLock.sample(released,left&&hostTrigger?2:0,other,now);
        if(fired)*fired=event==2;
        return hostLock.consumed;
    }
    // P1 R3+LT queues a party recall. It never directly moves any Pawn.
    bool sampleRecall(unsigned index,bool connected,const XINPUT_GAMEPAD& p,ULONGLONG now,bool* fired=nullptr) {
        if(fired)*fired=false;
        if(seat(index)!=0)return false;
        if(!connected){hostRecall={};recallTrigger=false;return false;}
        if(p.bLeftTrigger>=LOCK_TRIGGER_ON)recallTrigger=true;
        else if(p.bLeftTrigger<=LOCK_TRIGGER_OFF)recallTrigger=false;
        const bool right=(p.wButtons&XINPUT_GAMEPAD_RIGHT_THUMB)!=0;
        const bool other=(p.wButtons&(XINPUT_GAMEPAD_LEFT_THUMB|XINPUT_GAMEPAD_DPAD_DOWN|XINPUT_GAMEPAD_DPAD_UP))!=0;
        const bool conflict=other||p.bRightTrigger>LOCK_TRIGGER_OFF;
        const bool released=!right&&!recallTrigger&&!other&&p.bRightTrigger<=LOCK_TRIGGER_OFF;
        const int event=hostRecall.sample(released,right&&recallTrigger?2:0,conflict,now);
        if(event==2)++recall;
        if(fired)*fired=event==2;
        return hostRecall.consumed;
    }
    // Returns a button mask to consume in the game-visible XInput state.
    WORD sample(unsigned index,bool connected,const XINPUT_GAMEPAD& p,bool priority,ULONGLONG now,bool* fired=nullptr) {
        if(fired)*fired=false;
        if(index>=4)return 0;
        auto& h=pads[index];const int player=seat(index);
        if(!connected || player<0){h={};return 0;}
        const bool l=(p.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)!=0;
        const bool r=(p.wButtons&XINPUT_GAMEPAD_RIGHT_THUMB)!=0;
        const bool down=(p.wButtons&XINPUT_GAMEPAD_DPAD_DOWN)!=0;
        const bool up=(p.wButtons&XINPUT_GAMEPAD_DPAD_UP)!=0;
        const bool released=!r&&!l&&!down&&!up;
        const int requested=r&&down&&!up&&!l?1:l&&r&&!down&&!up&&player==0?2:0;
        const bool conflict=priority || (r&&up&&down) || (l&&(down||up)) || (l&&p.bRightTrigger>=LOCK_TRIGGER_ON);
        const int event=h.sample(released,requested,conflict,now);
        if(event==1)++camera[player];else if(event==2)++safe;
        if(fired)*fired=event!=0;
        // Consume only once a supported combo was observed. Guest R3+Up and
        // standalone directional buttons keep their ordinary game behavior.
        return h.consumed?WORD(XINPUT_GAMEPAD_RIGHT_THUMB|XINPUT_GAMEPAD_DPAD_UP|XINPUT_GAMEPAD_DPAD_DOWN|(h.action==2?XINPUT_GAMEPAD_LEFT_THUMB:0)):0;
    }
    void keys(bool control,bool alt,bool r,bool f,bool conflict,ULONGLONG now,bool captured=true) {
        if(!bound){keyboard={};return;}
        const bool released=!control&&!alt&&!r&&!f;
        const int requested=captured&&control&&alt&&r&&!f?1:captured&&control&&alt&&f&&!r?2:0;
        const int event=keyboard.sample(released,requested,conflict||(r&&f),now);
        if(event==1)++camera[0];else if(event==2)++safe;
    }
    std::string status(unsigned long long session,bool hook)const{
        std::string s="PBZRECINPUT1 "+std::to_string(session);
        for(auto n:camera)s+=" "+std::to_string(n);
        return s+=" "+std::to_string(safe)+" "+std::to_string(hook)+"\n";
    }
};
}
