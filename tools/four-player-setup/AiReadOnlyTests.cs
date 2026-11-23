using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;

// Run only after the newly built test executable has passed the requested scan.
// The preview constructor prevents live device/file initialization. The only
// non-preview action below is the actual read-only recheck, with no manifest in
// the isolated test output directory, so it cannot touch live game paths.
class AiReadOnlyTests {
    static int checks;
    const BindingFlags PrivateInstance=BindingFlags.Instance|BindingFlags.NonPublic;
    static FieldInfo Field(string name){return typeof(FourPlayerSetup).GetField(name,PrivateInstance);}
    static T Get<T>(object o,string name){return (T)Field(name).GetValue(o);}
    static void Set(object o,string name,object value){Field(name).SetValue(o,value);}
    static object Call(object o,string name,params object[] args){return typeof(FourPlayerSetup).GetMethod(name,PrivateInstance).Invoke(o,args);}
    static void Check(bool passed,string label){if(!passed)throw new Exception(label);checks++;}

    [STAThread] static void Main(){
        string manifest=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,@"AI升级\manifest.json");
        if(File.Exists(manifest))throw new Exception("Run this test in an isolated directory without an AI manifest.");
        string progress=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"四人设备设置绑定.txt");
        bool existed=File.Exists(progress);byte[] before=existed?File.ReadAllBytes(progress):null;
        Check(typeof(FourPlayerSetup).GetMethod("UpgradeAi",PrivateInstance)==null,"installation method removed");
        Check(typeof(FourPlayerSetup).GetMethod("QuoteArgument",BindingFlags.Static|BindingFlags.NonPublic)==null,"process argument builder removed");
        Check(Field("aiDialogUpgrade")==null,"installation button removed");
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        using(FourPlayerSetup form=new FourPlayerSetup(true)){
            using(Form panel=(Form)Call(form,"BuildAiPanel")){
                Button button=Get<Button>(form,"aiDialogCheck");
                Check(button.Text=="重新检查 AI 组件","read-only button label");
                Check(!button.Enabled,"preview does not run checks");
                Check(panel.Controls.OfType<Label>().Any(l=>l.Text.Contains("L3 ＋ RT") && l.Font.Bold),"bold controller instructions retained");
                DateTime marker=DateTime.UtcNow.AddDays(1);
                Set(form,"nextAiHash",marker);Call(form,"RecheckAi");
                Check(Get<DateTime>(form,"nextAiHash")==marker,"preview recheck is inert");
                Check(!Get<Timer>(form,"timer").Enabled,"preview timer remains stopped");
                // Deliberately bypass only Preview for this one read-only method.
                // The missing local manifest returns before any game hash/read.
                Set(form,"Preview",false);Set(form,"gameStarted",true);Set(form,"launchPending",true);
                Set(form,"observerOnly",true);Set(form,"ownsBindings",false);Set(form,"pairing",2);Set(form,"calibrating",3);
                int[] slots=(int[])Get<int[]>(form,"slots").Clone();int closed=0;
                form.FormClosed+=(a,b)=>closed++;
                Call(form,"UpdateAiPanel");
                Check(button.Enabled,"recheck available while game or launch is busy");
                Call(form,"RecheckAi");
                Check(!form.IsDisposed && !panel.IsDisposed && closed==0,"recheck does not close setup or panel");
                Check(!Get<Timer>(form,"timer").Enabled,"recheck does not stop or start timers");
                Check(Get<bool>(form,"observerOnly") && !Get<bool>(form,"ownsBindings"),"binding ownership untouched");
                Check(Get<int>(form,"pairing")==2 && Get<int>(form,"calibrating")==3,"device workflow untouched");
                Check(slots.SequenceEqual(Get<int[]>(form,"slots")),"controller assignment unchanged");
                Check(!Get<bool>(form,"aiInstalled"),"missing manifest is not accepted as installed");
                Check(Get<string>(form,"aiInstallText")=="未找到本版 AI 组件检查清单","missing manifest clearly reported");
                Check(Get<Label>(form,"aiDialogResult").Text.Contains("不安装或覆盖"),"read-only scope explained");
                Check(Get<string[]>(form,"aiPlayerText")[0]=="真人操作 · 不托管","host remains human controlled");
                Check(Get<string[]>(form,"aiPlayerText")[1]=="AI 组件尚未确认","unknown component is not an install instruction");
                Set(form,"Preview",true);
            }
        }
        Check(!File.Exists(manifest),"recheck did not create an AI manifest");
        Check(existed==File.Exists(progress) && (!existed || before.SequenceEqual(File.ReadAllBytes(progress))),"recheck did not write binding progress");
        Console.WriteLine("AI read-only recheck: "+checks+" checks passed");
    }
}
