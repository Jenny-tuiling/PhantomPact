#include "party_ai.hpp"
#include <cassert>
#include <iostream>
int main(){
 partyai::Control c{77};c.mode[1].device=1;c.mode[1].identity=123;
 c.focus(false,10);
 auto e=c.mode[1].epoch;
 auto msg=[&](unsigned seq,unsigned slot,unsigned epoch,unsigned on){return "PBZAISET1 77 "+std::to_string(seq)+" "+std::to_string(slot)+" "+std::to_string(epoch)+" "+std::to_string(on);};
 assert(c.request(msg(1,2,e,1),20,true));assert(c.mode[1].enabled);assert(!c.output(1,20).wButtons);
 assert(!c.request(msg(1,2,e,1),21,true));
 assert(!c.request(msg(2,1,1,1),22,true));assert(!c.mode[0].enabled);
 assert(!c.request(msg(3,3,1,1),23,true));
 c.focus(true,30);assert(c.mode[1].enabled);
 assert(!c.request(msg(4,2,e,0),31,true));assert(c.mode[1].enabled);
 assert(c.request(msg(5,2,c.mode[1].epoch,0),32,true));assert(!c.mode[1].enabled);
 assert(!c.request(msg(6,2,c.mode[1].epoch,1),33,false));
 assert(!c.request("PBZAISET1 78 7 2 1 1",34,true));
 assert(!c.request(msg(8,2,c.mode[1].epoch,1)+" extra",35,true));
 std::cout<<"UI requests: session, epoch, replay, P1, mapping, focus and explicit off passed\n";
}
