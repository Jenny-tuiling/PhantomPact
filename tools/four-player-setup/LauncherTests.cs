using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
class LauncherTests {
    static int count;
    static void Check(bool value,string name){if(!value)throw new Exception(name);count++;}
    static FieldInfo Field(string name){return typeof(FourPlayerSetup).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic);}
    static void Set(object o,string name,object value){Field(name).SetValue(o,value);}
    static T Get<T>(object o,string name){return (T)Field(name).GetValue(o);}
    static object Call(object o,string name,params object[] args){return typeof(FourPlayerSetup).GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(o,args);}
    [STAThread] static void Main(){
        var join=typeof(FourPlayerSetup).GetMethod("JoinTarget",BindingFlags.NonPublic|BindingFlags.Static);
        Func<int[],int[],int,int,int> target=(map,done,n,pad)=>(int)join.Invoke(null,new object[]{map,done,n,pad});
        Check(target(new[]{0,1,2,3},new[]{0,0,0,0},4,3)==0,"A claims first free seat");
        Check(target(new[]{3,1,2,0},new[]{7,0,0,0},4,3)==0,"confirmed device retains owner");
        Check(target(new[]{3,1,2,0},new[]{7,0,0,0},4,2)==1,"reserved disconnected seat not stolen");
        Check(target(new[]{-1,0,1,2},new[]{7,0,0,0},4,2)==1,"keyboard host skipped");
        Check(target(new[]{0,1,2,3},new[]{7,7,7,7},2,3)==-1,"inactive owned seat not reassigned");
        string good="PBZAI1 123 1 456\n2 1 8 0\n3 0 9 2\n4 0 3 0\n";AiRuntimeState state;
        Check(AiStatusReader.TryParse(good,out state),"valid native protocol");
        Check(state.Enabled[1] && !state.Enabled[0] && state.Reason[2]==2 && state.Epoch[1]==8,"row mapping protects P1");
        string[] bad={"",good+"extra\n",good.Replace("2 1 8 0","1 1 8 0"),good.Replace("3 0 9 2","2 0 9 2"),good.Replace("2 1 8 0","2 1 0 0"),good.Replace("123 1","123 0"),good.Replace("123 1","0 1"),good.Replace("2 1 8 0","2 1 8 5"),new string('x',1025),good.Replace("123","99999999999999999999999")};
        foreach(string value in bad)Check(!AiStatusReader.TryParse(value,out state),"malformed status rejected");
        DateTime now=DateTime.UtcNow;
        Check(AiStatusReader.Fresh(now,now.AddSeconds(-1),now.AddSeconds(-10),true),"fresh current session");
        Check(!AiStatusReader.Fresh(now,now.AddSeconds(-3),now.AddSeconds(-10),true),"stale status hidden");
        Check(!AiStatusReader.Fresh(now,now.AddSeconds(-1),now.AddSeconds(-0.5),true),"previous process status hidden");
        Check(!AiStatusReader.Fresh(now,now.AddSeconds(1),now.AddSeconds(-10),true),"future status hidden");
        Check(!AiStatusReader.Fresh(now,now,now.AddSeconds(-10),false),"stopped process status hidden");
        int mode;int[] slots;
        Check(AiStatusReader.TryBindings("1\n2\n4\n3\n",out mode,out slots) && slots[2]==3 && slots[3]==2 && mode==0,"existing assignments preserved");
        Check(AiStatusReader.TryBindings("0\n1\n3\n-1\n",out mode,out slots) && mode==1 && slots[0]==-1 && slots[3]==-2,"keyboard and inactive binding");
        Check(AiStatusReader.TryBindings("-1\n-1\n-1\n-1\n",out mode,out slots) && Array.TrueForAll(slots,s=>s==-2),"single player no fictional devices");
        foreach(string b in new[]{"1\n1\n3\n4","1\n0\n3\n4","1\n2\n3","1\n2\n3\n5","1\n2\n3\n-2"})Check(!AiStatusReader.TryBindings(b,out mode,out slots),"unsafe binding file rejected");
        for(int flags=0;flags<8;flags++){
            bool preview=(flags&1)!=0,observing=(flags&2)!=0,owns=(flags&4)!=0;
            Check(AiStatusReader.MayWriteBindings(preview,observing,owns)==(!preview&&!observing&&owns),"binding ownership gate");
        }
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        string progress=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"四人设备设置绑定.txt");
        bool existed=File.Exists(progress);string before=existed?File.ReadAllText(progress):null;
        using(FourPlayerSetup form=new FourPlayerSetup(true)){
            Check(!Get<Timer>(form,"timer").Enabled,"preview timer stopped");
            Check(Get<string[]>(form,"skinIds").SequenceEqual(new[]{"pbz_original","chenchen","xiaobao","zhubajie","fengfeng"}),"only requested skins retained");
            foreach(string method in new[]{"Poll","WatchGameAndLock","WriteBindings","SaveCalibration","CalibrationTick","StartGame","ChooseSkins","ChooseWeapons","RecheckAi"}){Call(form,method);Check(true,"preview inert entry "+method);}
            Set(form,"pairing",2);Set(form,"calibrating",3);Set(form,"gameStarted",false);Set(form,"launchPending",false);Set(form,"ownsBindings",false);Set(form,"observerOnly",false);
            Call(form,"ApplyGameObservation",true,now);
            Check(Get<bool>(form,"observerOnly")&&!Get<bool>(form,"ownsBindings"),"external game becomes read-only observer");
            Check(Get<int>(form,"pairing")==-1 && Get<int>(form,"calibrating")==-1,"observer cancels device mutations");
            Call(form,"ApplyGameObservation",false,now);
            Check(!Get<bool>(form,"observerOnly")&&!Get<bool>(form,"ownsBindings"),"exit clears observation ownership");
            Set(form,"gameStarted",false);Set(form,"launchPending",true);Set(form,"ownsBindings",true);Set(form,"observerOnly",false);
            Call(form,"ApplyGameObservation",true,now);
            Check(!Get<bool>(form,"observerOnly")&&Get<bool>(form,"ownsBindings"),"own successful launch retains binding ownership");
            Set(form,"gameStarted",false);Set(form,"launchPending",true);Set(form,"ownsBindings",true);Set(form,"launchDeadline",now.AddSeconds(-1));
            Call(form,"ApplyGameObservation",false,now);
            Check(!Get<bool>(form,"ownsBindings")&&!Get<bool>(form,"launchPending"),"failed launch timeout revokes ownership");
        }
        Check(existed==File.Exists(progress) && (!existed || before==File.ReadAllText(progress)),"preview made no progress-file writes");
        Console.WriteLine("Launcher: "+count+" checks passed");
    }
}
