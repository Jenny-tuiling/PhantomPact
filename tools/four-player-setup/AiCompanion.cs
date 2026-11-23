using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class AiRuntimeState {
    public ulong Session, Accepted;
    public readonly bool[] Enabled=new bool[4];
    public readonly int[] Reason=new int[4];
    public readonly ulong[] Epoch=new ulong[4];
}
public static class AiStatusReader {
    public static bool TryParse(string text,out AiRuntimeState state){
        state=null;if(text==null || text.Length>1024)return false;
        string[] lines=text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries);
        if(lines.Length!=4)return false;
        Match head=Regex.Match(lines[0],@"^PBZAI1 ([0-9]+) 1 ([0-9]+)$");
        ulong session,accepted;
        if(!head.Success || !ulong.TryParse(head.Groups[1].Value,out session) || session==0 || !ulong.TryParse(head.Groups[2].Value,out accepted))return false;
        AiRuntimeState next=new AiRuntimeState{Session=session,Accepted=accepted};int seen=0;
        for(int i=1;i<4;i++){
            Match row=Regex.Match(lines[i],@"^([234]) ([01]) ([0-9]+) ([0-4])$");ulong epoch;
            if(!row.Success || !ulong.TryParse(row.Groups[3].Value,out epoch) || epoch==0)return false;
            int slot=int.Parse(row.Groups[1].Value)-1;
            if((seen&(1<<slot))!=0)return false;seen|=1<<slot;
            next.Enabled[slot]=row.Groups[2].Value=="1";next.Reason[slot]=int.Parse(row.Groups[4].Value);next.Epoch[slot]=epoch;
        }
        if(seen!=14)return false;state=next;return true;
    }
    public static bool Fresh(DateTime now,DateTime written,DateTime gameStarted,bool running){
        double age=(now-written).TotalSeconds;
        return running && written>=gameStarted && age>=-0.5 && age<=2;
    }
    public static bool MayWriteBindings(bool preview,bool observing,bool owns){return !preview && !observing && owns;}
    public static bool TryBindings(string text,out int mode,out int[] slots){
        mode=0;slots=null;if(text==null || text.Length>128)return false;
        string[] lines=text.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries);if(lines.Length!=4)return false;
        int[] parsed=new int[4];HashSet<int> used=new HashSet<int>();
        for(int i=0;i<4;i++){
            int value;if(!int.TryParse(lines[i].Trim(),out value) || value< -1 || value>4 || (value==0 && i!=0))return false;
            if(value>0 && !used.Add(value))return false;
            parsed[i]=value==0?-1:value<0?-2:value-1;
        }
        mode=parsed[0]==-1?1:0;slots=parsed;return true;
    }
}
public sealed class AiManifestFile {public string path{get;set;}public string sha256{get;set;}}
public sealed class AiManifest {public string packageId{get;set;}public string launcher{get;set;}public AiManifestFile[] files{get;set;}public AiManifestFile[] guards{get;set;}}

partial class FourPlayerSetup {
    internal readonly bool Preview;
    bool observerOnly=false,ownsBindings=false;
    Label[] aiCardLabels=new Label[4];
    Button aiButton=new Button();
    DateTime nextAiStatus,nextAiHash;
    string aiInstallText="正在检查 AI 队友组件…";
    bool aiInstalled;
    string[] aiPlayerText={"真人操作 · 不托管","等待游戏启动","等待游戏启动","等待游戏启动"};
    Label aiDialogInstall,aiDialogResult;
    Label[] aiDialogPlayers;
    Button aiDialogCheck;
    static readonly string[] AiPayload={"dlls/main.dll","Scripts/localfour.lua","Scripts/localcoop.lua","Scripts/party_ai.lua","Scripts/party_ai_policy.lua","Scripts/party_controls.lua","Scripts/party_recovery.lua"};
    static string ProgramDir {get{return AppDomain.CurrentDomain.BaseDirectory;}}

    void InitializeAiUi(){
        aiButton.Text="AI 队友 · 托管";aiButton.SetBounds(465,24,135,38);
        aiButton.FlatStyle=FlatStyle.Flat;aiButton.BackColor=Color.FromArgb(52,104,145);aiButton.ForeColor=Color.White;
        aiButton.Click+=(a,b)=>ShowAiPanel();Controls.Add(aiButton);
    }
    void InitializePreview(){
        fourMode.Checked=true;playerCount.SelectedIndex=2;
        aiInstalled=true;aiInstallText="预览示例 · 本地 AI 队友";
        aiPlayerText=new[]{"真人操作 · 不托管","AI 托管中","真人操作","真人操作"};
        monitors.Text="预览：四名玩家的设置与托管状态";
        for(int i=0;i<4;i++){
            details[i].Text="手柄 "+(i+1)+" · 示例";live[i].Text="预览模式，不读取设备";
            tests[i].Text="✓ A 键   ✓ 左摇杆\n✓ 右摇杆";
            aiCardLabels[i].Text="屏幕 "+(i+1)+" · "+(i==0?"真人主玩家":aiPlayerText[i]);
        }
        activity.Text="手柄输入 → 对应玩家卡片亮起；完整快捷键见“按键说明”";
        message.Text="预览模式：不启动游戏、不更改绑定、不发送手柄输入。";
        launch.Text="启动 4 人模式";
    }
    internal void RenderPreview(string file){
        if(!Preview)throw new InvalidOperationException("Preview mode required");
        AutoScroll=false;FormBorderStyle=FormBorderStyle.None;ClientSize=new Size(1100,790);AutoScrollMinSize=Size.Empty;
        ShowInTaskbar=false;StartPosition=FormStartPosition.Manual;Location=new Point(-32000,-32000);Show();Application.DoEvents();PerformLayout();
        using(Bitmap bitmap=new Bitmap(ClientSize.Width,ClientSize.Height)){
            DrawToBitmap(bitmap,new Rectangle(Point.Empty,ClientSize));bitmap.Save(file,System.Drawing.Imaging.ImageFormat.Png);
        }
        for(int tab=1;tab<setupTabs.TabPages.Count;tab++){
            setupTabs.SelectedIndex=tab;Application.DoEvents();PerformLayout();
            using(Bitmap bitmap=new Bitmap(ClientSize.Width,ClientSize.Height)){
                DrawToBitmap(bitmap,new Rectangle(Point.Empty,ClientSize));
                bitmap.Save(Path.Combine(Path.GetDirectoryName(file),Path.GetFileNameWithoutExtension(file)+"-tab"+tab+".png"),System.Drawing.Imaging.ImageFormat.Png);
            }
        }
        setupTabs.SelectedIndex=0;SetCalibrationExpanded(true);ClientSize=new Size(810,620);Application.DoEvents();PerformLayout();
        using(Bitmap bitmap=new Bitmap(ClientSize.Width,ClientSize.Height)){
            DrawToBitmap(bitmap,new Rectangle(Point.Empty,ClientSize));
            bitmap.Save(Path.Combine(Path.GetDirectoryName(file),Path.GetFileNameWithoutExtension(file)+"-small.png"),System.Drawing.Imaging.ImageFormat.Png);
        }
        using(Form dialog=BuildAiPanel()){
            dialog.FormBorderStyle=FormBorderStyle.None;dialog.ShowInTaskbar=false;dialog.StartPosition=FormStartPosition.Manual;dialog.Location=new Point(-32000,-32000);dialog.Show();Application.DoEvents();dialog.PerformLayout();
            using(Bitmap bitmap=new Bitmap(dialog.ClientSize.Width,dialog.ClientSize.Height)){
                dialog.DrawToBitmap(bitmap,new Rectangle(Point.Empty,dialog.ClientSize));
                bitmap.Save(Path.Combine(Path.GetDirectoryName(file),Path.GetFileNameWithoutExtension(file)+"-AI.png"),System.Drawing.Imaging.ImageFormat.Png);
            }
        }
        using(Form dialog=BuildRecoveryPanel()){
            dialog.FormBorderStyle=FormBorderStyle.None;dialog.ShowInTaskbar=false;dialog.StartPosition=FormStartPosition.Manual;dialog.Location=new Point(-32000,-32000);dialog.Show();Application.DoEvents();dialog.PerformLayout();
            using(Bitmap bitmap=new Bitmap(dialog.ClientSize.Width,dialog.ClientSize.Height)){
                dialog.DrawToBitmap(bitmap,new Rectangle(Point.Empty,dialog.ClientSize));
                bitmap.Save(Path.Combine(Path.GetDirectoryName(file),Path.GetFileNameWithoutExtension(file)+"-recovery.png"),System.Drawing.Imaging.ImageFormat.Png);
            }
        }
    }
    void EnterReadOnlyObservation(){
        observerOnly=true;ownsBindings=false;pairing=-1;calibrating=-1;lastBindings="";
        AdoptRunningBindings();
        message.Text="已连接正在运行的游戏：只读显示设备与托管状态，不改动当前绑定。";
    }
    void AdoptRunningBindings(){
        if(Preview)return;
        try{
            int selectedMode;int[] adopted;
            if(AiStatusReader.TryBindings(File.ReadAllText(Path.Combine(Mod,"four_bindings.txt")),out selectedMode,out adopted)){
                mode.SelectedIndex=selectedMode;slots=adopted;
                for(int i=0;i<4;i++)checkedParts[i]=0; // observing a binding is not a completed device test
            }
        }catch(IOException){}catch(UnauthorizedAccessException){}
    }
    static string HashFile(string path){
        using(FileStream stream=File.OpenRead(path))using(SHA256 hash=SHA256.Create())
            return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","");
    }
    static T ReadJson<T>(string path){
        FileInfo info=new FileInfo(path);if(info.Length>1024*1024)throw new IOException("配置文件过大");
        return new JavaScriptSerializer().Deserialize<T>(File.ReadAllText(path));
    }
    static bool SafeRelative(string relative){
        return !string.IsNullOrEmpty(relative) && !Path.IsPathRooted(relative) && !relative.Contains(":") && !relative.Contains("\\") && !relative.Split('/').Any(p=>p==".." || p=="." || p.Length==0);
    }
    void CheckAiInstalled(){
        aiInstalled=false;
        try{
            string baseVersions=Path.Combine(ProgramDir,"BaseVersions");
            if(Directory.Exists(baseVersions)){
                string id=BaseSwitcher.VerifyComponents(baseVersions,Mod,AiPayload);
                aiInstalled=true;aiInstallText=id=="local"?"本地测试底座 · AI 组件校验通过":"稳定底座 · AI 组件校验通过";return;
            }
            string manifestPath=Path.Combine(ProgramDir,@"AI升级\manifest.json");
            if(!File.Exists(manifestPath)){aiInstallText="未找到本版 AI 组件检查清单";return;}
            AiManifest manifest=ReadJson<AiManifest>(manifestPath);
            if(manifest==null || manifest.files==null || manifest.files.Length!=AiPayload.Length || manifest.files.Select(f=>f.path).Distinct().Count()!=AiPayload.Length || AiPayload.Any(p=>!manifest.files.Any(f=>f.path==p)))throw new IOException("AI 组件清单不完整");
            foreach(AiManifestFile f in manifest.files.Concat(manifest.guards??new AiManifestFile[0])){
                if(!SafeRelative(f.path) || !Regex.IsMatch(f.sha256??"",@"\A[0-9A-Fa-f]{64}\z"))throw new IOException("AI 组件清单格式异常");
                string installed=Path.Combine(Mod,f.path.Replace('/',Path.DirectorySeparatorChar));
                if(!File.Exists(installed) || !string.Equals(HashFile(installed),f.sha256,StringComparison.OrdinalIgnoreCase)){
                    aiInstallText="AI 组件与本版清单不一致 · 仅检查，未修改文件";return;
                }
            }
            aiInstalled=true;aiInstallText="已安装本版 AI 队友";
        }catch(Exception ex){aiInstallText="AI 组件检查未完成："+ex.Message;}
    }

    void RefreshAiStatus(bool force){
        if(Preview)return;
        DateTime now=DateTime.UtcNow;
        if(!force && now<nextAiStatus)return;nextAiStatus=now.AddMilliseconds(500);
        if(force || now>=nextAiHash){nextAiHash=now.AddSeconds(5);CheckAiInstalled();}
        AiRuntimeState state=null;bool fresh=false;
        if(aiInstalled && gameStarted){
            try{
                string path=Path.Combine(Mod,"party_ai_status.txt");
                FileInfo info=new FileInfo(path);
                fresh=info.Exists && info.Length<=1024 && AiStatusReader.Fresh(now,info.LastWriteTimeUtc,gameStartUtc,gameStarted)
                    && AiStatusReader.TryParse(File.ReadAllText(path),out state);
            }catch(IOException){}catch(UnauthorizedAccessException){}
        }
        aiPlayerText[0]="真人操作 · 不托管";
        for(int i=1;i<4;i++){
            if(!aiInstalled)aiPlayerText[i]="AI 组件尚未确认";
            else if(!gameStarted)aiPlayerText[i]="待进入多人游戏";
            else if(i>=SelectedPlayers)aiPlayerText[i]="本次未加入";
            else if(!fresh)aiPlayerText[i]="状态未刷新 · 不确认托管";
            else if(state.Enabled[i])aiPlayerText[i]=state.Reason[i]==0?"AI 托管中":"AI 已开启 · 暂停操作，恢复后继续";
            else if(state.Reason[i]==1)aiPlayerText[i]="真人操作 · 托管已暂停";
            else if(state.Reason[i]==2)aiPlayerText[i]="真人操作 · 手柄断开";
            else if(state.Reason[i]==3)aiPlayerText[i]="真人操作 · 等待绑定";
            else if(state.Reason[i]==4)aiPlayerText[i]="真人操作 · 游戏失去焦点";
            else aiPlayerText[i]="真人操作";
        }
        for(int i=0;i<4;i++)if(aiCardLabels[i]!=null){
            aiCardLabels[i].Text="屏幕 "+(i+1)+" · "+(i==0?"真人主玩家":aiPlayerText[i]);
            aiCardLabels[i].ForeColor=fresh && i>0 && state.Enabled[i]?Color.MediumAquamarine:Color.Silver;
        }
        currentAiPageState=fresh?state:null;
        UpdateAiPanel();
    }
    AiRuntimeState currentAiPageState;
    Button[] aiSwitches=new Button[4];
    DateTime[] aiSent=new DateTime[4];
    bool[] aiWanted=new bool[4];
    void SubmitAiSwitch(int slot){
        if(Preview || currentAiPageState==null)return;
        RefreshAiStatus(true);if(currentAiPageState==null)return;
        try{
            var state=currentAiPageState;bool on=!state.Enabled[slot];
            string target=Path.Combine(Mod,"party_ai_set_"+(slot+1)+".txt"),temp=target+".tmp";
            File.WriteAllText(temp,"PBZAISET1 "+state.Session+" "+DateTime.UtcNow.Ticks+" "+(slot+1)+" "+state.Epoch[slot]+" "+(on?1:0)+"\n");
            if(File.Exists(target))File.Replace(temp,target,null);else File.Move(temp,target);
            aiSent[slot]=DateTime.UtcNow;aiWanted[slot]=on;UpdateAiPanel();
        }catch(Exception e){MessageBox.Show(this,e.Message,"AI 开关未提交");}
    }
    void UpdateAiPanel(){
        if(aiDialogInstall==null || aiDialogInstall.IsDisposed)return;
        aiDialogInstall.Text=aiInstallText;aiDialogInstall.ForeColor=aiInstalled?Color.MediumAquamarine:Color.Khaki;
        for(int i=0;i<4;i++)aiDialogPlayers[i].Text="玩家 "+(i+1)+"    "+aiPlayerText[i];
        for(int i=1;i<4;i++)if(aiSwitches[i]!=null){
            bool ready=currentAiPageState!=null && gameStarted && i<SelectedPlayers;
            bool enabled=ready && currentAiPageState.Enabled[i];
            bool pending=aiSent[i]!=default(DateTime) && (DateTime.UtcNow-aiSent[i]).TotalSeconds<5 && (!ready || enabled!=aiWanted[i]);
            aiSwitches[i].Enabled=!Preview && ready && !pending;
            aiSwitches[i].Text=!ready?"等待进入游戏":pending?"等待游戏确认…":enabled?"关闭 AI":"开启 AI";
            aiSwitches[i].UseVisualStyleBackColor=false;
            aiSwitches[i].BackColor=!ready || pending?Color.FromArgb(192,205,216):enabled?Color.FromArgb(47,112,104):Color.FromArgb(47,83,107);
            aiSwitches[i].ForeColor=Color.White;
        }
        aiDialogResult.Text=Preview?"预览模式：只展示界面，不读取游戏组件。":"开关与手柄快捷键同步；不安装或覆盖游戏文件。仅主动关闭或重启才退出托管。";
        aiDialogCheck.Enabled=!Preview;
        aiDialogCheck.Text="重新检查 AI 组件";
    }
    Form BuildAiPanel(){
        Form dialog=new Form{Text="AI 队友 · 小朋友快乐玩版",ClientSize=new Size(700,612),Font=Font,
            BackColor=Color.FromArgb(22,27,36),ForeColor=Color.White,StartPosition=FormStartPosition.CenterParent,
            FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false};
        Label heading=new Label{Text="累了就交给 AI，想玩随时接回",Font=new Font(Font.FontFamily,18,FontStyle.Bold)};
        heading.SetBounds(24,20,650,42);dialog.Controls.Add(heading);
        aiDialogInstall=new Label();aiDialogInstall.SetBounds(26,70,648,38);dialog.Controls.Add(aiDialogInstall);
        aiDialogPlayers=new Label[4];
        for(int i=0;i<4;i++){
            Label row=new Label{BackColor=Color.FromArgb(35,43,57),ForeColor=Color.White,TextAlign=ContentAlignment.MiddleLeft};
            row.SetBounds(26,113+i*44,470,37);dialog.Controls.Add(row);aiDialogPlayers[i]=row;
            if(i>0){int slot=i;var button=new Button{Text="开启 AI",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};button.SetBounds(506,113+i*44,168,37);button.Click+=(a,b)=>SubmitAiSwitch(slot);aiSwitches[i]=button;dialog.Controls.Add(button);}
        }
        Label guide=new Label{Text="2～4号手柄：L3 ＋ RT 同时按住 4 秒\n切换真人操作／AI托管；1号始终由真人操作。\nL3 = 左摇杆按下；RT = 右扳机。\n切换后松开两个按键，再按可再次切换。\n仅主动关闭或重启游戏才退出托管。\n死亡、传送、切出窗口、断线只暂停，恢复后继续。\n托管队友落后较远时自动安全归队。\n托管时，对应屏幕显示红色“AI托管中”提示。",Font=new Font(Font.FontFamily,12,FontStyle.Bold),ForeColor=Color.FromArgb(255,227,157)};
        guide.SetBounds(26,290,648,176);dialog.Controls.Add(guide);
        aiDialogResult=new Label{ForeColor=Color.Salmon,AutoEllipsis=true};aiDialogResult.SetBounds(26,468,648,48);dialog.Controls.Add(aiDialogResult);
        aiDialogCheck=new Button{FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(49,114,91),ForeColor=Color.White};
        aiDialogCheck.SetBounds(26,548,420,40);aiDialogCheck.Click+=(a,b)=>RecheckAi();dialog.Controls.Add(aiDialogCheck);
        Button close=new Button{Text="返回设置",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};close.SetBounds(470,548,204,40);close.Click+=(a,b)=>dialog.Close();dialog.Controls.Add(close);
        UpdateAiPanel();return dialog;
    }
    Panel BuildEmbeddedAiPanel(){
        Form shell=BuildAiPanel();Panel embedded=new Panel{Size=new Size(700,610)};
        foreach(Control control in shell.Controls.Cast<Control>().ToArray()){
            if(control is Button && control.Text=="返回设置")continue;
            embedded.Controls.Add(control);
        }
        embedded.Size=new Size(700,290);
        foreach(Control c in embedded.Controls){
            if(c is Label && c.Text.StartsWith("累了")){c.Text="AI 托管";c.SetBounds(12,8,460,36);}
            if(c is Label && c.Text.StartsWith("2～4号手柄"))c.Visible=false;
        }
        aiDialogInstall.SetBounds(12,48,650,24);
        for(int i=0;i<4;i++){aiDialogPlayers[i].SetBounds(12,80+i*40,470,34);if(i>0)aiSwitches[i].SetBounds(492,80+i*40,168,34);}
        aiDialogResult.SetBounds(12,244,650,40);
        aiDialogCheck.Visible=false;
        shell.Dispose();return embedded;
    }
    void ShowAiPanel(){RefreshAiStatus(true);using(Form dialog=BuildAiPanel())dialog.ShowDialog(this);}
    void RecheckAi(){
        if(Preview)return;
        RefreshAiStatus(true);
    }
}
