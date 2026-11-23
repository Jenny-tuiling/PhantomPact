#define NOMINMAX
#include <cassert>
#include <cstring>
#include <iostream>
#include <string>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"

using namespace partyai;
static_assert(HOLD_MS==4000);
Packet packetFor(const Control& c,unsigned long long seq,bool allow=true,WORD buttons=XINPUT_GAMEPAD_A) {
    Packet p;p.session=c.session;p.sequence=seq;
    for(unsigned i=0;i<3;i++){p.frame[i].slot=i+2;p.frame[i].epoch=c.mode[i+1].epoch;p.frame[i].allow=allow;p.frame[i].pad.wButtons=buttons;}
    return p;
}
void bindAll(Control& c,ULONGLONG now=100){for(unsigned s=1;s<4;s++)c.bind(s,s+1,1000+s,true,now);}
XINPUT_GAMEPAD combo(){XINPUT_GAMEPAD p{};p.wButtons=XINPUT_GAMEPAD_LEFT_THUMB;p.bRightTrigger=255;return p;}
ULONGLONG enable(Control& c,unsigned slot,ULONGLONG now,unsigned long long& seq) {
    c.raw(slot,{},now);c.raw(slot,combo(),now+1);
    c.accept(packetFor(c,++seq),now+HOLD_MS);
    assert(!c.raw(slot,combo(),now+HOLD_MS));
    assert(c.raw(slot,combo(),now+HOLD_MS+1));assert(c.mode[slot].enabled);
    return now+HOLD_MS+1;
}
int main() {
    Hold h;assert(!h.update(true,255,0));assert(!h.update(true,255,9999));
    h.update(false,0,10000);h.update(true,255,10100);
    assert(!h.update(true,255,14099));assert(h.update(true,255,14100));assert(!h.update(true,255,20000));
    h.update(false,255,20100);h.update(true,255,20200);assert(!h.update(true,255,25000));
    h.update(true,0,25100);h.update(true,255,25200);assert(!h.update(true,255,30000));
    h.update(false,32,30100);h.update(true,127,30200);assert(!h.update(true,127,35000));
    h.update(true,128,35100);h.update(true,80,36000);assert(h.update(true,80,39100));
    Hold interrupted;interrupted.update(false,0,0);interrupted.update(true,255,100);interrupted.update(false,255,1000);
    interrupted.update(true,255,2000);assert(!interrupted.update(true,255,5999));assert(interrupted.update(true,255,6000));
    Packet parsed;
    const std::string good="PBZAI1 22 1\n2 1 1 4096 0 0 32767 -32768 0 0\n3 1 0 0 0 0 0 0 0 0\n4 1 1 128 0 0 0 0 0 0\n";
    assert(parse(good,parsed));assert(parsed.frame[0].pad.sThumbLY==-32768);
    assert(!parse("PBZAI1 -1 1\n"+good.substr(good.find('\n')+1),parsed));
    assert(!parse(good+"trailing",parsed));assert(!parse(good.substr(0,good.size()-5),parsed));
    auto bad=good;bad.replace(bad.find("4096"),4,"64");assert(!parse(bad,parsed));
    bad=good;bad.replace(bad.find("32767"),5,"32768");assert(!parse(bad,parsed));
    bad=good;bad.replace(bad.find("3 1 0"),5,"2 1 0");assert(!parse(bad,parsed));
    bad=good;bad.replace(bad.find("2 1 1"),5,"1 1 1");assert(!parse(bad,parsed));
    Control c{22};bindAll(c);unsigned long long seq=0;
    c.raw(0,{},100);c.raw(0,combo(),101);assert(!c.raw(0,combo(),9999));assert(!c.mode[0].enabled);
    c.raw(1,{},100);c.raw(1,combo(),101);assert(!c.raw(1,combo(),4101));assert(!c.mode[1].enabled);
    auto t=enable(c,1,5000,seq);
    assert(c.output(1,t).wButtons==0);
    auto stale=packetFor(c,++seq);--stale.frame[0].epoch;c.accept(stale,t+10);assert(c.output(1,t+10).wButtons==0);
    auto frame=packetFor(c,++seq);assert(c.accept(frame,t+20));assert(c.output(1,t+20).wButtons==XINPUT_GAMEPAD_A);
    assert(!c.accept(frame,t+400));assert(c.output(1,t+20+FRESH_MS+1).wButtons==0);
    c.watchdog(t+20+WATCHDOG_MS+1);assert(c.mode[1].enabled && c.mode[1].reason==Watchdog && c.output(1,t+20+WATCHDOG_MS+1).wButtons==0);
    t=enable(c,2,t+2000,seq);c.accept(packetFor(c,++seq,false),t+10);
    assert(c.mode[2].enabled && c.output(2,t+11).wButtons==0);
    c.raw(2,{},t+20);c.raw(2,combo(),t+21);assert(c.raw(2,combo(),t+21+HOLD_MS));assert(!c.mode[2].enabled);
    t=enable(c,3,t+HOLD_MS+100,seq);auto before=c.mode[3].epoch;c.bind(3,4,9999,true,t+2);
    assert(c.mode[3].enabled && c.mode[3].epoch>before && c.output(3,t+2).wButtons==0);
    assert(!c.accept(Packet{99,++seq,{}},t+3));

    using namespace partyinput;
    ai=Control{22};locked=false;for(auto& chord:chords)chord={};for(auto& v:sequence)v=0;
    fourroute::Binding b;b.count=4;for(int i=0;i<4;i++){b.player[i]=1000+i;b.device[i]=i+1;}
    auto run=[&](unsigned index,XINPUT_GAMEPAD pad,ULONGLONG now,DWORD result=ERROR_SUCCESS,bool focus=true){
        b.updated=now;XINPUT_STATE state{};state.Gamepad=pad;transform(index,result,&state,b,focus,now);return state.Gamepad;
    };
    run(1,{},100);run(1,combo(),101);ai.accept(packetFor(ai,1),4100);
    auto triple=combo();triple.wButtons|=XINPUT_GAMEPAD_RIGHT_THUMB;
    auto preparing=run(1,triple,4100);
    assert((preparing.wButtons&XINPUT_GAMEPAD_LEFT_THUMB)==0 && preparing.bRightTrigger==0);
    assert(!ai.mode[1].enabled && sequence[1]==0);
    assert(run(1,triple,4101).wButtons==0);assert(ai.mode[1].enabled && sequence[1]==0);
    auto bot=packetFor(ai,2);bot.frame[0].pad.sThumbLX=12000;ai.accept(bot,4110);
    XINPUT_GAMEPAD physical{};physical.wButtons=XINPUT_GAMEPAD_B;
    auto output=run(1,physical,4111);assert(output.wButtons==XINPUT_GAMEPAD_A && output.sThumbLX==12000);
    auto host=run(0,physical,4112);assert(host.wButtons==XINPUT_GAMEPAD_B && !ai.mode[0].enabled);
    run(1,{},4120);run(1,combo(),4121);ai.accept(packetFor(ai,3,false),8120);
    output=run(1,combo(),8121);assert(!ai.mode[1].enabled && output.wButtons==0 && output.bRightTrigger==0);
    output=run(1,combo(),8200);assert(output.wButtons==0 && output.bRightTrigger==0);
    run(1,{},8210);assert(run(1,physical,8220).wButtons==XINPUT_GAMEPAD_B);
    run(2,{},9000);run(2,combo(),9001);ai.accept(packetFor(ai,4),13000);run(2,combo(),13001);assert(ai.mode[2].enabled);
    ai.accept(packetFor(ai,5),13002);assert(run(2,{},13003).wButtons==XINPUT_GAMEPAD_A);
    XINPUT_STATE unplugged{};b.updated=13010;
    assert(transform(2,ERROR_DEVICE_NOT_CONNECTED,&unplugged,b,true,13010)==ERROR_SUCCESS);
    assert(unplugged.Gamepad.wButtons==0 && ai.mode[2].enabled && ai.mode[2].reason==Disconnected);
    assert(transform(2,ERROR_DEVICE_NOT_CONNECTED,&unplugged,b,true,13011)==ERROR_DEVICE_NOT_CONNECTED);
    run(3,{},14000);run(3,combo(),14001);ai.accept(packetFor(ai,6),18000);run(3,combo(),18001);assert(ai.mode[3].enabled);
    run(3,{},18010,ERROR_SUCCESS,false);assert(ai.mode[3].enabled && ai.mode[3].reason==FocusLost);
    run(3,{},18011);assert(ai.mode[3].enabled && ai.output(3,18011).wButtons==0);
    unsigned long long nativeSeq=6;t=enable(ai,1,19000,nativeSeq);
    ai.accept(packetFor(ai,++nativeSeq),t+1);
    assert(run(1,{},t+2).wButtons==0);assert(run(1,{},t+3).wButtons==XINPUT_GAMEPAD_A);
    locked=true;ai.accept(packetFor(ai,++nativeSeq),t+4);assert(run(1,{},t+5).wButtons==0);
    run(2,{},t+100);run(2,combo(),t+101);ai.accept(packetFor(ai,++nativeSeq),t+100+HOLD_MS);
    run(2,combo(),t+101+HOLD_MS);assert(!ai.mode[2].enabled);
    std::cout<<"PASS: 4s AI boundary, hysteresis, rearm, strict protocol, replay/epoch/session, watchdog, pause, routing, P1 exclusion, handoff, disconnect/focus\n";
}
