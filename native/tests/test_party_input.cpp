#define NOMINMAX
#include <string>
#include <cassert>
#include <iostream>
namespace localio { inline void write_atomic(const std::wstring&,const std::string&){} }
#include "party_input.hpp"
int main(){
    using namespace partyinput;
    partyinput::Chord host;
    held(host,true,true,100,3000);
    assert(!held(host,true,true,2100,3000));
    assert(!held(host,true,true,3099,3000));
    assert(held(host,true,true,3100,3000));
    assert(!held(host,true,true,9000,3000));
    partyinput::Chord c;
    assert(!held(c,true,true,100));
    assert(!held(c,true,true,2099));
    assert(held(c,true,true,2100));
    assert(!held(c,true,true,5000));
    assert(!held(c,true,false,5100));
    assert(!held(c,true,true,8000)); // must release BOTH to rearm
    held(c,false,false,8100);
    held(c,true,true,8200);assert(held(c,true,true,10200));
    c={};held(c,true,true,100);held(c,false,true,1000);held(c,true,true,1100);
    assert(!held(c,true,true,3000));assert(held(c,true,true,3100));
    SHORT x=-6000,y=1800;stick(x,y,-6000,1800,2500);assert(x==0 && y==0);
    x=-5800;y=1600;stick(x,y,-6000,1800,2500);assert(x==0 && y==0);
    x=32767;y=1800;stick(x,y,-6000,1800,2500);assert(x==32767 && y==0);
    x=-32768;y=1800;stick(x,y,-6000,1800,2500);assert(x==-32767 && y==0);
    x=-6000;y=1800;stick(x,y,0,0,0);assert(x==-6000 && y==1800);
    for(int center=-32768;center<=32767;center++) {
        x=static_cast<SHORT>(center);y=static_cast<SHORT>(center);
        stick(x,y,center,center,2500);assert(x==0 && y==0);
    }
    x=-32768;y=32767;stick(x,y,-32768,32767,2500);assert(x==0 && y==0);
    x=32767;y=0;stick(x,y,-32768,0,2500);assert(x==32767 && y==0);
    x=-32768;y=0;stick(x,y,32767,0,2500);assert(x==-32767 && y==0);
    std::cout<<"PASS: hold duration, one-shot/rearm, interrupted hold, center/noise/endpoints/default\n";
}
