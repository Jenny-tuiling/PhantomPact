#define NOMINMAX
#include "local_io.hpp"
#include <string>
#include <vector>
#include <algorithm>
#include <cassert>
#include <iostream>
#include <cstdio>

#include "screens.hpp"
int main(){
    std::vector<screens::Box> monitors={{0,0,3840,2160},{3840,0,3840,2160},{7680,0,3840,2160},{11520,0,3840,2160}};
    for(int count=2;count<=4;count++){
        auto p=screens::plan_four(monitors,count);assert(p.ok && p.window.w==3840*count && p.window.h==2160);
    }
    assert(!screens::plan_four({monitors[0],monitors[1]},3).ok);
    monitors[1].x+=100;assert(!screens::plan_four(monitors,2).ok);
    std::cout<<"PASS: 2/3/4 selected monitor spans, insufficient/gapped monitors rejected\n";
}

