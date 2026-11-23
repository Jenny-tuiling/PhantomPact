using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public static class RecoveryRequestQueue {
    public const string RequestName="recovery_requests.txt",StatusName="recovery_status.txt";
    public const string ReadyName="recovery_ready.txt",HookName="recovery_input_status.txt";
    public static void Submit(string directory,string id,string action,int seat){
        if(!Regex.IsMatch(id??"",@"\A[A-Za-z0-9-]{1,80}\z"))throw new ArgumentException("Invalid request id");
        if((action!="camera" && action!="safe") || seat<1 || seat>4 || (action=="safe" && seat!=1))throw new ArgumentException("Invalid recovery command");
        if(!Directory.Exists(directory))throw new DirectoryNotFoundException("多人模块目录不存在。");
        string target=Path.Combine(directory,RequestName),temp=target+"."+Guid.NewGuid().ToString("N")+".tmp";
        try{
            File.WriteAllText(temp,"PBZREC1 "+id+" "+action+" "+seat+"\n",Encoding.ASCII);
            File.Move(temp,target); // Atomic create: never replace another pending UI request.
        }finally{if(File.Exists(temp))File.Delete(temp);}
    }
    public static bool TryReadStatus(string directory,string expectedId,out string state,out string message){
        state=null;message=null;
        if(!Regex.IsMatch(expectedId??"",@"\A[A-Za-z0-9-]{1,80}\z"))return false;
        string path=Path.Combine(directory,StatusName);
        try{
            FileInfo info=new FileInfo(path);if(!info.Exists || info.Length>4096)return false;
            string line=File.ReadAllText(path,Encoding.UTF8).TrimEnd('\r','\n');
            Match match=Regex.Match(line,@"\APBZREC1 ([A-Za-z0-9-]{1,80}) (ok|blocked|error) ([^\r\n]{1,1000})\z");
            if(!match.Success || match.Groups[1].Value!=expectedId)return false;
            state=match.Groups[2].Value;message=match.Groups[3].Value;return true;
        }catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}
    }
    static bool FreshLine(string directory,string name,DateTime now,DateTime gameStart,out string text){
        text=null;
        try{
            string path=Path.Combine(directory,name);FileInfo info=new FileInfo(path);
            double age=(now-info.LastWriteTimeUtc).TotalSeconds;
            if(!info.Exists || info.Length>256 || info.LastWriteTimeUtc<gameStart || age< -0.5 || age>5)return false;
            text=File.ReadAllText(path,Encoding.ASCII).TrimEnd('\r','\n');return true;
        }catch(IOException){return false;}catch(UnauthorizedAccessException){return false;}
    }
    public static bool TryReadReady(string directory,DateTime now,DateTime gameStart,out int count){
        count=0;string text;if(!FreshLine(directory,ReadyName,now,gameStart,out text))return false;
        Match match=Regex.Match(text,@"\APBZRECOVERY1 [0-9-]{1,80} ([234])\z");
        if(!match.Success)return false;count=int.Parse(match.Groups[1].Value);return true;
    }
    public static string HookNotice(string directory,DateTime now,DateTime gameStart){
        string text;if(!FreshLine(directory,HookName,now,gameStart,out text))return "恢复快捷键状态尚未确认；模块就绪后可用页面按钮。";
        Match match=Regex.Match(text,@"\APBZRECHOOK1 ([01]) ([01]) ([0-9]{1,10})\z");uint error;
        if(!match.Success || !uint.TryParse(match.Groups[3].Value,out error))return "恢复快捷键状态尚未确认；模块就绪后可用页面按钮。";
        bool pads=match.Groups[1].Value=="1",keys=match.Groups[2].Value=="1";
        if(!pads && !keys)return "手柄和键盘恢复快捷键尚未就绪，可用页面按钮。";
        if(!keys)return "键盘恢复快捷键尚未就绪，可用手柄或页面按钮。";
        if(!pads)return "手柄恢复快捷键尚未就绪，可用键盘或页面按钮。";
        return "手柄与键盘恢复快捷键已就绪。";
    }
}

partial class FourPlayerSetup {
    Button recoveryButton=new Button();
    Button[] recoveryCameras=new Button[4];
    Button recoverySafe;
    Label recoveryMessage,recoveryHookMessage;
    DateTime nextRecoveryCheck,recoverySentAt;
    string pendingRecoveryId="",recoveryText="恢复工具已就绪，选择需要恢复的玩家。";
    Color recoveryColor=Color.Silver;
    int recoverySerial;

    void InitializeRecoveryUi(){
        recoveryButton.Text="视角 / 脱困";recoveryButton.SetBounds(900,24,150,38);
        recoveryButton.FlatStyle=FlatStyle.Flat;recoveryButton.BackColor=Color.FromArgb(114,83,42);recoveryButton.ForeColor=Color.White;
        recoveryButton.Click+=(a,b)=>ShowRecoveryPanel();Controls.Add(recoveryButton);
    }
    int RecoveryRouteSeatCount(){
        if(Preview)return 4;
        if(!gameStarted)return 0;
        try{
            string path=Path.Combine(Mod,"four_route.txt");FileInfo info=new FileInfo(path);
            double age=(DateTime.UtcNow-info.LastWriteTimeUtc).TotalSeconds;
            if(info.Exists && info.Length<=256 && age>=-0.5 && age<=3 && info.LastWriteTimeUtc>=gameStartUtc){
                string[] lines=File.ReadAllLines(path);int count;
                if(lines.Length==5 && int.TryParse(lines[4].Trim(),out count) && count>=2 && count<=4)return count;
            }
        }catch(IOException){}catch(UnauthorizedAccessException){}
        return 0;
    }
    int RecoverySeatCount(out string unavailable){
        unavailable="";
        if(Preview)return 4;
        if(!gameStarted){unavailable="请从多人模式启动后使用恢复工具。";return 0;}
        int count;bool ready=RecoveryRequestQueue.TryReadReady(Mod,DateTime.UtcNow,gameStartUtc,out count);
        if(!ready && RecoveryRouteSeatCount()<2 && !fourMode.Checked){unavailable="请从多人模式启动后使用恢复工具。";return 0;}
        if(!aiInstalled){unavailable="恢复组件尚未就绪，请退出游戏后更新完整多人模块。";return 0;}
        if(!ready){
            string path=Path.Combine(Mod,RecoveryRequestQueue.ReadyName);
            unavailable=File.Exists(path)&&File.GetLastWriteTimeUtc(path)>=gameStartUtc?
                "恢复模块状态未刷新，暂不能发送请求。请等待游戏恢复运行。":"恢复模块加载中，正在等待本次多人游戏确认。";
            return 0;
        }
        return count;
    }
    void RefreshRecoveryUi(bool force=false){
        if(!force && DateTime.UtcNow<nextRecoveryCheck)return;
        nextRecoveryCheck=DateTime.UtcNow.AddMilliseconds(250);
        if(!Preview && pendingRecoveryId.Length>0){
            string state,detail;
            if(RecoveryRequestQueue.TryReadStatus(Mod,pendingRecoveryId,out state,out detail)){
                recoveryText=(state=="ok"?"游戏已确认：":"本次未执行：")+detail;
                recoveryColor=state=="ok"?Color.MediumAquamarine:Color.Salmon;pendingRecoveryId="";
            }else if((DateTime.UtcNow-recoverySentAt).TotalSeconds>=10){
                recoveryText="尚未收到游戏确认。请求不会自动重发；请等待游戏恢复运行。";
                recoveryColor=Color.Khaki;
            }
        }
        bool queued=!Preview && File.Exists(Path.Combine(Mod,RecoveryRequestQueue.RequestName));
        string unavailable;int count=RecoverySeatCount(out unavailable);
        for(int i=0;i<4;i++)if(recoveryCameras[i]!=null && !recoveryCameras[i].IsDisposed)recoveryCameras[i].Enabled=!Preview && i<count && !queued;
        if(recoverySafe!=null && !recoverySafe.IsDisposed)recoverySafe.Enabled=!Preview && count>0 && !queued;
        if(recoveryMessage!=null && !recoveryMessage.IsDisposed){
            recoveryMessage.Text=Preview?"预览模式：按钮不发送任何游戏请求。":count==0?unavailable:recoveryText;
            recoveryMessage.ForeColor=Preview?Color.Silver:count==0?Color.Khaki:recoveryColor;
        }
        if(recoveryHookMessage!=null && !recoveryHookMessage.IsDisposed){
            recoveryHookMessage.Text=Preview?"多人模式内可用；快捷键状态会在游戏运行后显示。":gameStarted?RecoveryRequestQueue.HookNotice(Mod,DateTime.UtcNow,gameStartUtc):"仅供 2／3／4 人模式使用。";
        }
    }
    void SendRecoveryRequest(string action,int seat){
        if(Preview)return;
        try{
            if(FindGameProcesses().Length==0)throw new InvalidOperationException("请先进入游戏，再使用恢复功能。");
            CheckAiInstalled();
            string unavailable;int count=RecoverySeatCount(out unavailable);
            if(count==0)throw new InvalidOperationException(unavailable);
            if(seat>count)throw new InvalidOperationException("这位玩家当前没有加入。");
            string id=DateTime.UtcNow.Ticks+"-"+Process.GetCurrentProcess().Id+"-"+(++recoverySerial);
            RecoveryRequestQueue.Submit(Mod,id,action,seat);
            pendingRecoveryId=id;recoverySentAt=DateTime.UtcNow;
            recoveryText="请求已发送，等待游戏检查并处理。";recoveryColor=Color.Khaki;
        }catch(IOException ex){
            recoveryText=File.Exists(Path.Combine(Mod,RecoveryRequestQueue.RequestName))?"上一条请求正在处理，请稍候。":"请求未发送："+ex.Message;
            recoveryColor=Color.Salmon;
        }catch(Exception ex){recoveryText="请求未发送："+ex.Message;recoveryColor=Color.Salmon;}
        RefreshRecoveryUi(true);
    }
    Form BuildRecoveryPanel(){
        Form dialog=new Form{Text="视角恢复与安全脱困",ClientSize=new Size(740,620),Font=Font,
            BackColor=Color.FromArgb(22,27,36),ForeColor=Color.White,StartPosition=FormStartPosition.CenterParent,
            FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false};
        Label title=new Label{Text="视角恢复与安全脱困",Font=new Font(Font.FontFamily,19,FontStyle.Bold)};
        title.SetBounds(24,18,690,40);dialog.Controls.Add(title);
        Label note=new Label{Text="仅供 2／3／4 人模式。正常接地行走或站立满1秒会自动记点。\n1号只返回15米内已检查的落点；无法执行时会提示原因。",ForeColor=Color.Silver};
        note.SetBounds(26,68,690,51);dialog.Controls.Add(note);
        for(int i=0;i<4;i++){
            int seat=i+1;Button button=new Button{Text="玩家 "+seat+" · 恢复视角",FlatStyle=FlatStyle.Flat,ForeColor=Color.White,BackColor=Color.FromArgb(52,104,145),Font=new Font(Font.FontFamily,13,FontStyle.Bold)};
            button.SetBounds(26+(i%2)*348,132+(i/2)*63,336,52);button.Click+=(a,b)=>SendRecoveryRequest("camera",seat);
            dialog.Controls.Add(button);recoveryCameras[i]=button;
        }
        recoverySafe=new Button{Text="玩家1 · 返回最近安全位置",FlatStyle=FlatStyle.Flat,ForeColor=Color.White,BackColor=Color.FromArgb(114,83,42),Font=new Font(Font.FontFamily,13,FontStyle.Bold)};
        recoverySafe.SetBounds(26,265,684,52);recoverySafe.Click+=(a,b)=>SendRecoveryRequest("safe",1);dialog.Controls.Add(recoverySafe);
        Label keys=new Label{Text="所有玩家手柄：R3 ＋ 方向键↓ 按住2秒，恢复自己的视角。\n1号手柄：L3 ＋ R3 按住3秒，安全脱困。\n1号手柄：R3 ＋ LT 按住3秒，逐个召回可归队的队友。\n1号键盘：左Ctrl ＋ 左Alt ＋ R 按住2秒，恢复视角。\n1号键盘：左Ctrl ＋ 左Alt ＋ F 按住3秒，安全脱困。\nL3 = 左摇杆按下；R3 = 右摇杆按下；LT = 左扳机。",ForeColor=Color.FromArgb(255,227,157),Font=new Font(Font.FontFamily,11,FontStyle.Bold)};
        keys.SetBounds(26,336,684,132);dialog.Controls.Add(keys);
        recoveryHookMessage=new Label{ForeColor=Color.Khaki};recoveryHookMessage.SetBounds(26,472,684,31);dialog.Controls.Add(recoveryHookMessage);
        recoveryMessage=new Label{ForeColor=Color.Silver};recoveryMessage.SetBounds(26,510,684,43);dialog.Controls.Add(recoveryMessage);
        Button close=new Button{Text="返回设置",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};close.SetBounds(506,561,204,38);close.Click+=(a,b)=>dialog.Close();dialog.Controls.Add(close);
        RefreshRecoveryUi(true);return dialog;
    }
    void ShowRecoveryPanel(){using(Form dialog=BuildRecoveryPanel())dialog.ShowDialog(this);}
}
