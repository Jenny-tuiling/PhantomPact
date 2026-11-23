using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

class RecoveryTests {
    static int count;
    static void Check(bool value,string name){if(!value)throw new Exception(name);count++;}
    static void Rejected(Action action,string name){try{action();throw new Exception("Accepted invalid input: "+name);}catch(ArgumentException){count++;}}
    [STAThread] static void Main(){
        string root=Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        string fixture=Path.GetFullPath(Path.Combine(root,"RecoveryFixture-"+Guid.NewGuid().ToString("N")));
        if(!fixture.StartsWith(root,StringComparison.OrdinalIgnoreCase))throw new Exception("Fixture escaped workspace");
        Directory.CreateDirectory(fixture);
        try{
            string request=Path.Combine(fixture,RecoveryRequestQueue.RequestName),status=Path.Combine(fixture,RecoveryRequestQueue.StatusName);
            string[] protectedFiles={"four_actions.txt","four_bindings.txt","four_calibration.txt"};
            foreach(string file in protectedFiles)File.WriteAllText(Path.Combine(fixture,file),"existing-"+file);
            for(int seat=1;seat<=4;seat++){
                string id="seat-"+seat;
                RecoveryRequestQueue.Submit(fixture,id,"camera",seat);
                Check(File.ReadAllText(request)=="PBZREC1 "+id+" camera "+seat+"\n","camera seat protocol "+seat);
                File.Delete(request);
            }
            RecoveryRequestQueue.Submit(fixture,"safe-1","safe",1);
            Check(File.ReadAllText(request)=="PBZREC1 safe-1 safe 1\n","host-only safe protocol");
            try{RecoveryRequestQueue.Submit(fixture,"other","camera",2);throw new Exception("Pending request overwritten");}catch(IOException){Check(File.ReadAllText(request)=="PBZREC1 safe-1 safe 1\n","existing pending request preserved");}
            Check(Directory.GetFiles(fixture,"*.tmp").Length==0,"temporary files cleaned after failed create");
            File.Delete(request);
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,"bad\nid","camera",1),"id newline");
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,new string('a',81),"camera",1),"id length");
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,"id","unknown",1),"action");
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,"id","safe",2),"safe guest");
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,"id","camera",0),"seat zero");
            Rejected(()=>RecoveryRequestQueue.Submit(fixture,"id","camera",5),"seat five");
            string state,detail;
            foreach(string verdict in new[]{"ok","blocked","error"}){
                File.WriteAllText(status,"PBZREC1 active "+verdict+" 游戏回执说明\n",new UTF8Encoding(false));
                Check(RecoveryRequestQueue.TryReadStatus(fixture,"active",out state,out detail)&&state==verdict&&detail=="游戏回执说明","matching UTF-8 receipt "+verdict);
                Check(!RecoveryRequestQueue.TryReadStatus(fixture,"old-id",out state,out detail),"different request receipt ignored");
            }
            foreach(string bad in new[]{"PBZREC1 active done no","PBZREC1 active ok first\nPBZREC1 active ok second","PBZREC1 active ok ",new string('x',4097)}){
                File.WriteAllText(status,bad);Check(!RecoveryRequestQueue.TryReadStatus(fixture,"active",out state,out detail),"malformed receipt ignored");
            }
            string ready=Path.Combine(fixture,RecoveryRequestQueue.ReadyName),hooks=Path.Combine(fixture,RecoveryRequestQueue.HookName);
            DateTime now=DateTime.UtcNow,started=now.AddMinutes(-1);int seats;
            Check(!RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats),"missing heartbeat is not ready");
            for(int players=2;players<=4;players++){
                File.WriteAllText(ready,"PBZRECOVERY1 123-456 "+players+"\n");File.SetLastWriteTimeUtc(ready,now);
                Check(RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats)&&seats==players,"fresh active multiplayer count "+players);
            }
            foreach(string bad in new[]{"PBZRECOVERY1 123 1","PBZRECOVERY1 123 5","PBZRECOVERY1 letters 4","PBZRECOVERY1 123 4\nother",new string('x',257)}){
                File.WriteAllText(ready,bad);File.SetLastWriteTimeUtc(ready,now);
                Check(!RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats),"invalid readiness rejected");
            }
            File.WriteAllText(ready,"PBZRECOVERY1 123 4\n");
            File.SetLastWriteTimeUtc(ready,now.AddSeconds(-6));Check(!RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats),"stale readiness disabled");
            File.SetLastWriteTimeUtc(ready,started.AddSeconds(-1));Check(!RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats),"prior process readiness disabled");
            File.SetLastWriteTimeUtc(ready,now.AddSeconds(1));Check(!RecoveryRequestQueue.TryReadReady(fixture,now,started,out seats),"future readiness rejected");
            File.WriteAllText(hooks,"PBZRECHOOK1 1 0 5\n");File.SetLastWriteTimeUtc(hooks,now);
            Check(RecoveryRequestQueue.HookNotice(fixture,now,started).StartsWith("键盘恢复"),"keyboard hook failure explains alternative");
            File.WriteAllText(hooks,"PBZRECHOOK1 0 1 5\n");File.SetLastWriteTimeUtc(hooks,now);
            Check(RecoveryRequestQueue.HookNotice(fixture,now,started).StartsWith("手柄恢复"),"gamepad hook failure explains alternative");
            File.WriteAllText(hooks,"PBZRECHOOK1 0 0 5\n");File.SetLastWriteTimeUtc(hooks,now);
            Check(RecoveryRequestQueue.HookNotice(fixture,now,started).Contains("手柄和键盘"),"both hook failures keep page-button alternative");
            File.WriteAllText(hooks,"PBZRECHOOK1 1 1 0\n");File.SetLastWriteTimeUtc(hooks,now);
            Check(RecoveryRequestQueue.HookNotice(fixture,now,started).EndsWith("已就绪。"),"fresh hook success shown");
            File.SetLastWriteTimeUtc(hooks,now.AddSeconds(-6));Check(RecoveryRequestQueue.HookNotice(fixture,now,started).Contains("尚未确认"),"stale hook status is not success");
            int sent=0,refused=0;Exception unexpected=null;ManualResetEvent start=new ManualResetEvent(false);Thread[] threads=new Thread[2];
            for(int i=0;i<2;i++){int slot=i;threads[i]=new Thread(()=>{start.WaitOne();try{RecoveryRequestQueue.Submit(fixture,"race-"+slot,"camera",slot+1);Interlocked.Increment(ref sent);}catch(IOException){Interlocked.Increment(ref refused);}catch(Exception ex){unexpected=ex;}});threads[i].Start();}
            start.Set();foreach(Thread thread in threads)Check(thread.Join(5000),"concurrent writer completed");
            Check(unexpected==null && sent==1 && refused==1,"atomic queue permits exactly one writer");
            string pending=File.ReadAllText(request);Check(pending=="PBZREC1 race-0 camera 1\n"||pending=="PBZREC1 race-1 camera 2\n","concurrent request remains one complete line");
            Check(Directory.GetFiles(fixture,"*.tmp").Length==0,"concurrent temporary files cleaned");
            foreach(string file in protectedFiles)Check(File.ReadAllText(Path.Combine(fixture,file))=="existing-"+file,"native/assignment file untouched: "+file);
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            using(FourPlayerSetup form=new FourPlayerSetup(true)){
                MethodInfo send=typeof(FourPlayerSetup).GetMethod("SendRecoveryRequest",BindingFlags.Instance|BindingFlags.NonPublic);
                send.Invoke(form,new object[]{"camera",1});send.Invoke(form,new object[]{"safe",1});
                FieldInfo id=typeof(FourPlayerSetup).GetField("pendingRecoveryId",BindingFlags.Instance|BindingFlags.NonPublic);
                Check((string)id.GetValue(form)=="","preview recovery actions inert");
                typeof(FourPlayerSetup).GetField("Preview",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(form,false);
                MethodInfo readiness=typeof(FourPlayerSetup).GetMethod("RecoverySeatCount",BindingFlags.Instance|BindingFlags.NonPublic);
                object[] argument={null};Check((int)readiness.Invoke(form,argument)==0 && ((string)argument[0]).Contains("多人模式"),"non-running game cannot expose an executable recovery button");
            }
            Console.WriteLine("Recovery UI: "+count+" checks passed");
        }finally{
            string checkedPath=Path.GetFullPath(fixture);
            if(checkedPath.StartsWith(root,StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(checkedPath).StartsWith("RecoveryFixture-",StringComparison.Ordinal))Directory.Delete(checkedPath,true);
        }
    }
}
