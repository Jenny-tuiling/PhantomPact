using System;
using System.Drawing;
using System.IO;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

class StickPreview : Control {
    public short LX,LY,RX,RY;
    public StickPreview(){DoubleBuffered=true;Size=new Size(213,90);}
    protected override void OnPaint(PaintEventArgs e){
        e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        for(int i=0;i<2;i++){
            int x=i==0?52:160,y=32; short ax=i==0?LX:RX,ay=i==0?LY:RY;
            using(Pen pen=new Pen(Color.FromArgb(110,135,160),2))e.Graphics.DrawEllipse(pen,x-24,y-24,48,48);
            e.Graphics.DrawLine(Pens.DimGray,x-24,y,x+24,y);e.Graphics.DrawLine(Pens.DimGray,x,y-24,x,y+24);
            float dx=x+ax/32768f*21,dy=y-ay/32768f*21;
            e.Graphics.FillEllipse(Brushes.MediumAquamarine,dx-6,dy-6,12,12);
            e.Graphics.DrawString(i==0?"左摇杆":"右摇杆",Font,Brushes.White,x-24,62);
        }
    }
}

class PartyLockBadge : Form {
    Label label=new Label();
    public PartyLockBadge(){
        FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;
        StartPosition=FormStartPosition.Manual;ClientSize=new Size(460,88);
        BackColor=Color.FromArgb(155,30,35);Opacity=0.93;
        label.Dock=DockStyle.Fill;label.ForeColor=Color.White;
        label.Font=new Font("Microsoft YaHei UI",15,FontStyle.Bold);
        label.TextAlign=ContentAlignment.MiddleCenter;Controls.Add(label);
    }
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams {get{CreateParams p=base.CreateParams;p.ExStyle|=0x08000000|0x20|0x80;return p;}}
    public void UpdateState(bool locked,int player){
        BackColor=locked?Color.FromArgb(155,30,35):Color.FromArgb(25,110,65);
        label.Text=locked?(player==0?"队友操作已锁定\n1号 L3＋RT 按住3秒解锁":"主机已锁定操作\n双摇杆按住3秒可归队"):"队友操作已恢复";
    }
}

partial class FourPlayerSetup : Form {
    string EditionName(){
        if(Preview)return "小朋友快乐玩版";
        string file=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"版本名称.txt");
        if(File.Exists(file)){string name=File.ReadAllText(file).Trim();if(name.Length>0 && name.Length<=60)return name;}
        return "小朋友快乐玩版";
    }
    readonly string[] skinIds={"pbz_original","chenchen","xiaobao","zhubajie","fengfeng"};
    readonly string[] skinNames={"原始魂大人","辰辰","小宝","猪八戒","枫枫"};
    void ChooseWeapons(){
        if(Preview || observerOnly)return;
        string catalog=Path.Combine(Mod,"party_weapon_catalog.txt");
        if(!File.Exists(catalog)){MessageBox.Show(this,"请先用新版进入存档，读取已拥有武器后再打开此页。");return;}
        string[] ids=new[]{"default"}.Concat(File.ReadAllLines(catalog).Where(x=>x.Contains("\t")).Select(x=>x.Split('\t')[0])).ToArray();
        string path=Path.Combine(Mod,"party_weapons.txt");
        string[] saved=File.Exists(path)?File.ReadAllLines(path):new string[0];
        using(Form dialog=new Form()){
            dialog.Text="队友武器 · 共用已拥有武器";dialog.ClientSize=new Size(530,330);dialog.Font=Font;dialog.StartPosition=FormStartPosition.CenterParent;
            Label note=new Label{Text="1号使用游戏原装备菜单。队友收刀后应用选择。\n当前仅列出已确认资源对应的武器（显示内部名称）。",AutoSize=true};note.Location=new Point(15,15);dialog.Controls.Add(note);
            ComboBox[] picks=new ComboBox[3];
            for(int i=0;i<3;i++){
                Label label=new Label{Text="玩家 "+(i+2),AutoSize=true};label.Location=new Point(20,90+i*55);dialog.Controls.Add(label);
                picks[i]=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Enabled=i+2<=SelectedPlayers};picks[i].Items.AddRange(ids);
                picks[i].SelectedIndex=i+1<saved.Length?Math.Max(0,Array.IndexOf(ids,saved[i+1])):0;picks[i].SetBounds(130,85+i*55,370,32);dialog.Controls.Add(picks[i]);
            }
            Button save=new Button{Text="保存队友武器"};save.SetBounds(300,270,200,40);dialog.Controls.Add(save);
            save.Click+=(a,b)=>{try{File.WriteAllLines(path,new[]{"default"}.Concat(picks.Select(p=>ids[p.SelectedIndex])).ToArray(),new UTF8Encoding(false));dialog.Close();}catch(Exception ex){MessageBox.Show(dialog,ex.Message);}};
            dialog.ShowDialog(this);
        }
    }
    void ChooseSkins(){
        if(Preview || observerOnly)return;
        if(Busy){MessageBox.Show(this,"请退出游戏后选择下次使用的皮肤。");return;}
        string path=Path.Combine(Path.GetDirectoryName(Mod),"PBZWardrobe","player_skins.txt");
        using(Form dialog=new Form()){
            dialog.Text="每位玩家的皮肤 · 下次启动生效";dialog.ClientSize=new Size(500,320);
            dialog.StartPosition=FormStartPosition.CenterParent;dialog.Font=Font;
            ComboBox[] picks=new ComboBox[4];
            string[] saved=File.Exists(path)?File.ReadAllLines(path):new string[0];
            for(int i=0;i<4;i++){
                Label label=new Label{Text="玩家 "+(i+1)+(i>=SelectedPlayers?"（本次未加入）":""),AutoSize=true};
                label.SetBounds(20,25+i*52,170,30);dialog.Controls.Add(label);
                picks[i]=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Enabled=i<SelectedPlayers};
                picks[i].Items.AddRange(skinNames);picks[i].SelectedIndex=i<saved.Length?Math.Max(0,Array.IndexOf(skinIds,saved[i])):0;
                picks[i].SetBounds(200,20+i*52,275,32);dialog.Controls.Add(picks[i]);
            }
            Button save=new Button{Text="保存皮肤选择"};save.SetBounds(280,255,195,40);dialog.Controls.Add(save);
            save.Click+=(a,b)=>{try{
                if(!Directory.Exists(Path.GetDirectoryName(path)))throw new Exception("尚未安装多人皮肤适配模块。");
                File.WriteAllLines(path,picks.Select(p=>skinIds[p.SelectedIndex]).ToArray(),new UTF8Encoding(false));dialog.Close();
            }catch(Exception ex){MessageBox.Show(dialog,ex.Message,"保存未完成");}};
            dialog.ShowDialog(this);
        }
    }

    static readonly string Mod = ResolveMod();
    static string ResolveMod(){
        string root=AppDomain.CurrentDomain.BaseDirectory;
        string adjacent=Path.GetFullPath(Path.Combine(root,".."));
        if(File.Exists(Path.Combine(adjacent,"Scripts","pbz.lua")))return adjacent;
        string config=Path.Combine(root,"game-path.txt");
        if(File.Exists(config))return Path.Combine(File.ReadAllText(config).Trim(),@"platform\steam\ue4ss\Mods\PBZCoop");
        return @"D:\Program Files (x86)\Steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PBZCoop";
    }
    [StructLayout(LayoutKind.Sequential)] public struct Pad { public ushort buttons; public byte lt,rt; public short lx,ly,rx,ry; }
    [StructLayout(LayoutKind.Sequential)] public struct State { public uint packet; public Pad pad; }
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("xinput1_4.dll")] static extern uint XInputGetState(uint index,out State state);
    [StructLayout(LayoutKind.Sequential)] struct Vibration {public ushort left,right;}
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("xinput1_4.dll")] static extern uint XInputSetState(uint index,ref Vibration vibration);
    DateTime[] rumbleUntil=new DateTime[4];
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    PartyLockBadge[] lockBadges=new PartyLockBadge[4];
    DateTime nextGameCheck, nextLockCheck, unlockedUntil;
    int[] gamePids=new int[0];bool lastLocked=false;
    bool launchPending=false; DateTime launchDeadline,gameStartUtc;
    bool Busy {get{return gameStarted || launchPending;}}
    int[] slots={0,1,2,3}, checkedParts=new int[4];
    bool[] connected=new bool[4], wasConnected=new bool[4];
    State[] states=new State[4]; ushort[] previous=new ushort[4];
    Label[] details=new Label[4], tests=new Label[4]; Button[] bind=new Button[4];
    Panel[] cards=new Panel[4]; Label[] live=new Label[4]; StickPreview[] sticks=new StickPreview[4];
    Label activity=new Label();
    ComboBox mode=new ComboBox(); Label message=new Label(), monitors=new Label();
    Button launch=new Button(); Timer timer=new Timer();
    CheckBox fourMode=new CheckBox();
    ComboBox playerCount=new ComboBox();
    int SelectedPlayers {get{return fourMode.Checked?playerCount.SelectedIndex+2:1;}}
    int pairing=-1; bool gameStarted=false, keysTested=false, mouseTested=false;
    int[,] centers=new int[4,4]; int[,] deadzones=new int[4,2];
    int calibrating=-1, samples=0; DateTime calibrateStart;
    long[] sums=new long[4]; int[] minimum=new int[4],maximum=new int[4];
    string calibrationPath=Path.Combine(Mod,"four_calibration.txt");
    string lastBindings="";
    string lastProgress="";
    readonly string progressPath=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"四人设备设置绑定.txt");

    public FourPlayerSetup(bool preview=false) {
        Preview=preview;
        Text=EditionName()+" · 影之刃零"; ClientSize=new Size(1080,880);
        MinimumSize=new Size(900,600); StartPosition=FormStartPosition.CenterScreen;
        AutoScroll=true;AutoScrollMinSize=new Size(1080,880);
        Rectangle desktopArea=Screen.PrimaryScreen.WorkingArea;
        ClientSize=new Size(Math.Min(1080,desktopArea.Width-32),Math.Min(880,desktopArea.Height-64));
        BackColor=Color.FromArgb(22,27,36); ForeColor=Color.White;
        Font=new Font("Microsoft YaHei UI",10); KeyPreview=true;
        Button skins=new Button{Text="每人选择皮肤",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};
        Button weapons=new Button{Text="队友选择武器",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};weapons.SetBounds(610,24,135,38);weapons.Click+=(a,b)=>ChooseWeapons();Controls.Add(weapons);
        skins.SetBounds(755,24,135,38);skins.Click+=(a,b)=>ChooseSkins();Controls.Add(skins);
        Label title=LabelAt(EditionName(),28,22,425,45,22);
        InitializeAiUi();
        InitializeRecoveryUi();
        InitializeTempPowerUi();
        LabelAt("① 先点玩家卡片“绑定 / 测试” → ② 按该手柄 A → ③ 分别推动左右摇杆。每位玩家依次操作。",30,77,1020,32,11);
        mode.SetBounds(30,122,310,34); mode.DropDownStyle=ComboBoxStyle.DropDownList;
        mode.Items.AddRange(new object[]{"全部玩家使用手柄","玩家 1 键鼠 ＋ 其他玩家手柄"}); mode.SelectedIndex=0;
        mode.SelectedIndexChanged+=(s,e)=>ResetMode(); Controls.Add(mode);
        fourMode.Text="开启多人模式（默认关闭）";
        fourMode.SetBounds(370,112,350,26);fourMode.ForeColor=Color.LightGreen;Controls.Add(fourMode);
        playerCount.DropDownStyle=ComboBoxStyle.DropDownList;playerCount.Items.AddRange(new object[]{"2 人模式","3 人模式","4 人模式"});playerCount.SelectedIndex=2;
        playerCount.SetBounds(735,110,250,30);Controls.Add(playerCount);
        fourMode.CheckedChanged+=(s,e)=>{if(!gameStarted)message.Text=fourMode.Checked?"请选择人数，完成启用玩家的绑定测试后启动。":"单人模式：不需要多块屏幕或多个手柄，直接启动即可。";};
        monitors=LabelAt("",370,142,680,35,10);
        for(int i=0;i<4;i++) {
            int player=i; int x=30+i*260;
            Panel card=new Panel {BackColor=Color.FromArgb(35,43,57)};
            cards[i]=card;card.SetBounds(x,183,245,480); Controls.Add(card);
            Label head=new Label {Text="玩家 "+(i+1),Font=new Font(Font.FontFamily,17,FontStyle.Bold),ForeColor=Color.White};
            head.SetBounds(16,18,215,40); card.Controls.Add(head);
            Label screen=new Label {Text="屏幕 "+(i+1)+" · 从左到右",ForeColor=Color.Silver};
            aiCardLabels[i]=screen;
            screen.SetBounds(16,68,215,30); card.Controls.Add(screen);
            details[i]=new Label {ForeColor=Color.White}; details[i].SetBounds(16,105,215,40); card.Controls.Add(details[i]);
            live[i]=new Label {Text="等待输入…",ForeColor=Color.LightGreen}; live[i].SetBounds(16,148,215,36);card.Controls.Add(live[i]);
            sticks[i]=new StickPreview();sticks[i].Location=new Point(16,192);card.Controls.Add(sticks[i]);
            tests[i]=new Label {ForeColor=Color.Silver}; tests[i].SetBounds(16,285,215,50); card.Controls.Add(tests[i]);
            bind[i]=new Button {Text="更换手柄",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};
            bind[i].SetBounds(16,340,212,38); bind[i].Click+=(s,e)=>Pair(player); card.Controls.Add(bind[i]);
            Button calibrate=new Button {Text="归中校准",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};
            calibrate.SetBounds(16,387,102,34);calibrate.Click+=(s,e)=>Calibrate(player);card.Controls.Add(calibrate);
            Button reset=new Button {Text="恢复默认",FlatStyle=FlatStyle.Flat,ForeColor=Color.White};
            reset.SetBounds(126,387,102,34);reset.Click+=(s,e)=>ClearCalibration(player);card.Controls.Add(reset);
            Label note=new Label {Text="校准时松开两根摇杆\n换手柄后请恢复默认或重新校准",ForeColor=Color.Silver};
            note.SetBounds(16,429,215,45);card.Controls.Add(note);
        }
        activity=LabelAt("动一动手柄：对应玩家卡片会亮起",30,675,1020,40,17);activity.ForeColor=Color.MediumAquamarine;
        message=LabelAt("依次点击每位玩家的“绑定 / 测试”，再按对应手柄的 A 键。",30,723,1020,44,11);
        launch.SetBounds(745,794,305,55); launch.Text="设备就绪 · 进入游戏";
        launch.BackColor=Color.FromArgb(49,114,91); launch.ForeColor=Color.White; launch.FlatStyle=FlatStyle.Flat;
        launch.Click+=(s,e)=>StartGame(); Controls.Add(launch);AcceptButton=launch;
        Button aboutButton=new Button{Text="关于 / 第三方致谢",FlatStyle=FlatStyle.Flat,ForeColor=Color.Silver};
        aboutButton.SetBounds(745,854,305,30);aboutButton.Visible=false;Controls.Add(aboutButton);
        AutoScrollMinSize=new Size(1080,1245);
        InitializeShortcutHelp();
        InitializeCompactLayout(title,skins,weapons,aboutButton);
        KeyDown+=(s,e)=>{if(mode.SelectedIndex==1){activity.Text="玩家 1 · 键盘输入："+e.KeyCode;live[0].Text="键盘："+e.KeyCode;if("WASD".Contains(e.KeyCode.ToString())){keysTested=true;checkedParts[0]=mouseTested?7:1;}}};
        MouseDown+=RecordMouseTest;
        timer.Interval=40; timer.Tick+=(s,e)=>Poll(); if(!Preview)timer.Start();
        FormClosing+=(s,e)=>{if(Busy){e.Cancel=true;WindowState=FormWindowState.Minimized;}};
        ResetMode();
        if(Preview){InitializePreview();return;}
        LoadCalibration();
        try {
            string[] saved=File.ReadAllLines(progressPath);
            if(saved.Length==5) {
                mode.SelectedIndex=int.Parse(saved[0]);
                for(int i=0;i<4;i++) {string[] pair=saved[i+1].Split(' ');slots[i]=int.Parse(pair[0]);checkedParts[i]=int.Parse(pair[1]);}
            }
        } catch(Exception) { }
        gamePids=FindGameProcesses();gameStarted=gamePids.Length>0;
        if(gameStarted){EnterReadOnlyObservation();mode.Enabled=false;launch.Text="游戏已运行";}
        RefreshAiStatus(true);
    }
    Label LabelAt(string text,int x,int y,int w,int h,int size) {
        Label l=new Label {Text=text,ForeColor=Color.White,Font=new Font(Font.FontFamily,size)};
        l.SetBounds(x,y,w,h); Controls.Add(l); return l;
    }
    void RecordMouseTest(object sender,MouseEventArgs e){
        if(Preview || observerOnly)return;
        if(mode.SelectedIndex==1){activity.Text="玩家 1 · 鼠标："+e.Button;live[0].Text="鼠标已响应";mouseTested=true;checkedParts[0]=keysTested?7:2;}
    }
    void ResetMode() {
        if(gameStarted) return;
        for(int i=0;i<4;i++){slots[i]=mode.SelectedIndex==1?i-1:i;checkedParts[i]=0;}
        pairing=-1;keysTested=mouseTested=false; lastBindings="";
    }
    void Pair(int player) {
        if(Preview || observerOnly || gameStarted || launchPending)return;
        if(slots[player]==-1) {message.Text="键鼠测试：点击页面空白处，然后按 W/A/S/D。"; return;}
        pairing=player;checkedParts[player]=0;
        message.Text="请按玩家 "+(player+1)+" 手柄的 A 键（先松开再按下）。";
    }
    static int JoinTarget(int[] map,int[] confirmed,int count,int device){
        int owner=Array.IndexOf(map,device);
        if(owner>=0 && confirmed[owner]>0)return owner<count?owner:-1;
        for(int i=0;i<count;i++)if(map[i]!=-1 && confirmed[i]==0)return i;
        return -1;
    }
    void Poll() {
        if(Preview)return;
        WatchGameAndLock();
        RefreshAiStatus(false);
        RefreshRecoveryUi();
        RefreshTempPowerUi();
        for(int s=0;s<4;s++) {wasConnected[s]=connected[s];connected[s]=XInputGetState((uint)s,out states[s])==0;}
        CalibrationTick();
        for(int s=0;s<4;s++)if(rumbleUntil[s]!=DateTime.MinValue && DateTime.UtcNow>=rumbleUntil[s]){Vibration v=new Vibration();XInputSetState((uint)s,ref v);rumbleUntil[s]=DateTime.MinValue;}
        // Automatic joining never reassigns a confirmed seat, including disconnected seats.
        if(!gameStarted && !launchPending && !observerOnly && fourMode.Checked && ContainsFocus){
            for(int s=0;s<4;s++)if(pairing<0 && connected[s] && wasConnected[s] && (states[s].pad.buttons&4096)!=0 && (previous[s]&4096)==0){
                int owner=Array.IndexOf(slots,s);
                if(owner>=0 && checkedParts[owner]>0){if(owner<SelectedPlayers)checkedParts[owner]=7;continue;}
                pairing=JoinTarget(slots,checkedParts,SelectedPlayers,s);
                break;
            }
        }
        for(int s=0;s<4;s++) if(!gameStarted && !launchPending && !observerOnly && pairing>=0 && connected[s] && (states[s].pad.buttons&4096)!=0 && (previous[s]&4096)==0) {
            int owner=Array.IndexOf(slots,s);
            if(owner>=0 && owner!=pairing) {slots[owner]=slots[pairing];checkedParts[owner]=0;}
            slots[pairing]=s;checkedParts[pairing]=7;
            Vibration vib=new Vibration {left=16000,right=16000};XInputSetState((uint)s,ref vib);rumbleUntil[s]=DateTime.UtcNow.AddMilliseconds(180);
            message.Text="玩家 "+(pairing+1)+" 已加入，可以直接启动；摇杆偏移时使用归中校准。";pairing=-1;break;
        }
        for(int i=0;i<4;i++) {
            cards[i].Visible=i<SelectedPlayers;
            cards[i].Enabled=true; foreach(Control child in cards[i].Controls)if(child is Button)child.Enabled=i<SelectedPlayers && !observerOnly;
            bind[i].Enabled=i<SelectedPlayers && !observerOnly && !gameStarted && !launchPending;
            if(i>=SelectedPlayers){details[i].Text="本次未加入";live[i].Text="选择更多人数可启用";tests[i].Text="无需绑定或测试";cards[i].BackColor=Color.FromArgb(35,43,57);continue;}
            int slot=slots[i];
            if(slot==-1){details[i].Text="键盘和鼠标";tests[i].Text=checkedParts[i]==7?"✓ 键盘与鼠标已确认":"点击空白处＋W/A/S/D";continue;}
            bool on=slot>=0 && slot<4 && connected[slot];
            Pad state=on?Correct(states[slot].pad,slot):new Pad();
            string input=Describe(state);
            live[i].Text=on?(input.Length>0?input:"等待输入…"):"等待手柄连接";
            sticks[i].LX=state.lx;sticks[i].LY=state.ly;sticks[i].RX=state.rx;sticks[i].RY=state.ry;sticks[i].Invalidate();
            cards[i].BackColor=pairing==i?Color.FromArgb(78,58,110):input.Length>0?Color.FromArgb(30,87,73):Color.FromArgb(35,43,57);
            bind[i].Text=pairing==i?"按 A 确认":"更换手柄";
            if(input.Length>0)activity.Text="正在输入：手柄 "+(slot+1)+" → 玩家 "+(i+1)+" · "+input;
            details[i].Text=slot<0?"等待绑定":("手柄 "+(slot+1)+(on?" · 已连接":" · 断开，保留此玩家"));
            if(on && checkedParts[i]>0) {
                Pad p=states[slot].pad;
                if(Math.Abs((int)p.lx)>16000 || Math.Abs((int)p.ly)>16000)checkedParts[i]|=2;
                if(Math.Abs((int)p.rx)>16000 || Math.Abs((int)p.ry)>16000)checkedParts[i]|=4;
            }
            if(slot>=0 && wasConnected[slot] && !on) message.Text="玩家 "+(i+1)+" 的手柄已断开，位置保留。原槽位重连会恢复；编号变化时请重新绑定。";
            tests[i].Text=pairing==i?"请松开 A，再按一次确认":checkedParts[i]>0?"✓ 已加入 · 断线保留玩家":"按手柄 A 即可加入";
            tests[i].ForeColor=checkedParts[i]==7 && on?Color.LightGreen:Color.Silver;
        }
        for(int s=0;s<4;s++)previous[s]=states[s].pad.buttons;
        Screen[] screens=Screen.AllScreens.OrderBy(s=>s.Bounds.Left).ToArray();
        int count=SelectedPlayers;
        bool four=screens.Length>=count;
        if(four)for(int i=1;i<count;i++)four &= screens[i].Bounds.Left==screens[i-1].Bounds.Right && screens[i].Bounds.Top==screens[0].Bounds.Top && screens[i].Bounds.Size==screens[0].Bounds.Size;
        monitors.Text=count==1?"单人模式：使用游戏原来的显示设置":four?"✓ 使用从左到右的前 "+count+" 块显示器":"请准备 "+count+" 块等尺寸、横向相邻的显示器";
        bool ready=four && checkedParts.Take(count).All(v=>v==7) && slots.Take(count).All(s=>s==-1 || (s>=0 && connected[s]));
        launch.Enabled=!Busy;
        launch.Text=launchPending?"正在等待游戏启动…":gameStarted?"游戏运行中":fourMode.Checked?(ready?"启动 ":"检查并启动 ")+count+" 人模式":"启动单人模式";
        mode.Enabled=!Busy;fourMode.Enabled=!Busy;
        playerCount.Enabled=fourMode.Checked && !Busy;
        string progress=mode.SelectedIndex+"\n"+string.Join("\n",slots.Select((s,i)=>s+" "+checkedParts[i]).ToArray());
        if(!observerOnly && progress!=lastProgress){try{File.WriteAllText(progressPath,progress,Encoding.UTF8);lastProgress=progress;}catch(IOException){}catch(UnauthorizedAccessException){}}
        if(gameStarted && ownsBindings) {
            try {WriteBindings();}
            catch(IOException) {message.Text="设备设置暂时未写入，正在重试；原分配保留。";}
            catch(UnauthorizedAccessException) {message.Text="无法写入游戏设备设置，请关闭此页面后重新打开。";}
        }
    }
    string Describe(Pad p) {
        var names=new System.Collections.Generic.List<string>();
        ushort[] mask={4096,8192,16384,32768,256,512,16,32,64,128,1,2,4,8};
        string[] text={"A","B","X","Y","LB","RB","菜单","返回","左摇杆按下","右摇杆按下","↑","↓","←","→"};
        for(int i=0;i<mask.Length;i++)if((p.buttons&mask[i])!=0)names.Add(text[i]);
        if(p.lt>35)names.Add("LT");if(p.rt>35)names.Add("RT");
        if(Math.Abs((int)p.lx)>7000||Math.Abs((int)p.ly)>7000)names.Add("左摇杆");
        if(Math.Abs((int)p.rx)>7000||Math.Abs((int)p.ry)>7000)names.Add("右摇杆");
        return string.Join(" + ",names.ToArray());
    }
    void LoadCalibration() {
        try {
            string[] lines=File.ReadAllLines(calibrationPath);
            if(lines.Length!=4)return;
            for(int i=0;i<4;i++) {
                int[] values=lines[i].Split(new char[]{' '},StringSplitOptions.RemoveEmptyEntries).Select(int.Parse).ToArray();
                if(values.Length!=6 || values.Take(4).Any(v=>v < -32768 || v > 32767) || values.Skip(4).Any(v=>v<0||v>9000))return;
                for(int j=0;j<4;j++)centers[i,j]=values[j];for(int j=0;j<2;j++)deadzones[i,j]=values[j+4];
            }
        }catch(Exception){}
    }
    void SaveCalibration() {
        if(Preview || observerOnly)return;
        StringBuilder text=new StringBuilder();
        for(int i=0;i<4;i++)text.AppendLine(string.Join(" ",Enumerable.Range(0,6).Select(j=>j<4?centers[i,j]:deadzones[i,j-4]).ToArray()));
        string tmp=calibrationPath+".tmp";File.WriteAllText(tmp,text.ToString(),Encoding.ASCII);
        if(File.Exists(calibrationPath))File.Replace(tmp,calibrationPath,null);else File.Move(tmp,calibrationPath);
    }
    void Calibrate(int player) {
        if(Preview || observerOnly)return;
        int slot=slots[player];
        if(slot<0||!connected[slot]){message.Text="请先连接并绑定这位玩家的手柄。";return;}
        calibrating=slot;calibrateStart=DateTime.UtcNow;samples=0;
        for(int j=0;j<4;j++){sums[j]=0;minimum[j]=32767;maximum[j]=-32768;}
        message.Text="玩家 "+(player+1)+"：请松开两根摇杆，保持不动 4 秒；正在准备采样。";
    }
    void ClearCalibration(int player) {
        if(Preview || observerOnly)return;
        int slot=slots[player];if(slot<0)return;calibrating=-1;
        for(int j=0;j<4;j++)centers[slot,j]=0;for(int j=0;j<2;j++)deadzones[slot,j]=0;
        try{SaveCalibration();message.Text="玩家 "+(player+1)+" 已恢复手柄默认输入；绑定保持不变。";}
        catch(Exception ex){message.Text="保存失败："+ex.Message;LoadCalibration();}
    }
    void CalibrationTick() {
        if(Preview || observerOnly)return;
        if(calibrating<0)return;
        int slot=calibrating;double elapsed=(DateTime.UtcNow-calibrateStart).TotalSeconds;
        if(!connected[slot]){calibrating=-1;message.Text="校准已取消：手柄断开。";return;}
        if(elapsed<1.5)return;
        Pad p=states[slot].pad;
        if(p.buttons!=0 || p.lt>30 || p.rt>30){calibrating=-1;message.Text="校准取消：请松开所有按键后重试。";return;}
        int[] values={p.lx,p.ly,p.rx,p.ry};
        for(int j=0;j<4;j++){sums[j]+=values[j];minimum[j]=Math.Min(minimum[j],values[j]);maximum[j]=Math.Max(maximum[j],values[j]);}
        samples++;
        if(elapsed<4)return;
        calibrating=-1;
        if(samples<30 || Enumerable.Range(0,4).Any(j=>maximum[j]-minimum[j]>2000)) {
            message.Text="校准未保存：采样不足或摇杆在采样时明显移动。支持全部偏移范围，请松手放稳后重试。";return;
        }
        int[] old=new int[6];for(int j=0;j<6;j++)old[j]=j<4?centers[slot,j]:deadzones[slot,j-4];
        for(int j=0;j<4;j++)centers[slot,j]=(int)(sums[j]/samples);
        for(int j=0;j<2;j++)deadzones[slot,j]=Math.Max(2500,Math.Max(maximum[j*2]-minimum[j*2],maximum[j*2+1]-minimum[j*2+1])+1000);
        try{SaveCalibration();message.Text="手柄 "+(slot+1)+" 归中校准已保存；请试松手和推满摇杆，游戏内也会生效。";}
        catch(Exception ex){for(int j=0;j<6;j++){if(j<4)centers[slot,j]=old[j];else deadzones[slot,j-4]=old[j];}message.Text="校准保存失败："+ex.Message;}
    }
    static double Center(short v,int c){double d=(double)v-c;if(d==0)return 0;return Math.Max(-32767,Math.Min(32767,d/(d>=0?32767-c:32768+c)*32767));}
    void CorrectStick(ref short x,ref short y,int slot,int stick) {
        int cx=centers[slot,stick*2],cy=centers[slot,stick*2+1],dead=deadzones[slot,stick];
        if(cx==0 && cy==0 && dead==0)return;
        double a=Center(x,cx),b=Center(y,cy),length=Math.Sqrt(a*a+b*b);
        if(length<=dead){x=y=0;return;}
        double gain=Math.Min(32767,(length-dead)*32767/(32767-dead))/length;
        x=(short)(a*gain);y=(short)(b*gain);
    }
    Pad Correct(Pad p,int slot){CorrectStick(ref p.lx,ref p.ly,slot,0);CorrectStick(ref p.rx,ref p.ry,slot,1);return p;}
    int[] FindGameProcesses(){
        var ids=new System.Collections.Generic.List<int>();
        string expected=Path.GetFullPath(Path.Combine(Mod,@"..\..\..\PBZ.exe"));
        gameStartUtc=DateTime.MaxValue;
        foreach(Process p in Process.GetProcessesByName("PBZ"))using(p){
            try{
                if(p.HasExited)continue;
                bool match;
                try{match=string.Equals(p.MainModule.FileName,expected,StringComparison.OrdinalIgnoreCase);}
                catch(System.ComponentModel.Win32Exception){match=p.MainWindowHandle!=IntPtr.Zero;}
                if(!match)continue;
                DateTime start=p.StartTime.ToUniversalTime();
                ids.Add(p.Id);if(start<gameStartUtc)gameStartUtc=start;
            }catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}
        }
        return ids.ToArray();
    }
    void ApplyGameObservation(bool active,DateTime now){
        if(active){
            bool ownLaunch=launchPending && ownsBindings;
            launchPending=false;
            if(!gameStarted){
                gameStarted=true;lastBindings="";
                if(!ownLaunch)EnterReadOnlyObservation();
                else message.Text="游戏已运行。退出游戏后，启动按钮会自动恢复。";
            }
        }
        else if(gameStarted){gameStarted=false;launchPending=false;observerOnly=false;ownsBindings=false;fourMode.Checked=false;lastBindings="";message.Text="游戏已退出，可以重新选择人数并启动；当前默认单人。";}
        else if(launchPending && now>=launchDeadline){launchPending=false;ownsBindings=false;observerOnly=false;message.Text="未检测到游戏成功启动。请检查Steam提示后重试；启动按钮已恢复。";}
    }
    string ReadinessProblem(){
        if(!fourMode.Checked)return "";
        int count=SelectedPlayers;
        var missing=new System.Collections.Generic.List<string>();
        Screen[] screens=Screen.AllScreens.OrderBy(s=>s.Bounds.Left).ToArray();
        if(screens.Length<count)missing.Add("需要 "+count+" 块显示器，目前只有 "+screens.Length+" 块");
        else for(int i=1;i<count;i++)if(screens[i].Bounds.Left!=screens[i-1].Bounds.Right || screens[i].Bounds.Top!=screens[0].Bounds.Top || screens[i].Bounds.Size!=screens[0].Bounds.Size){missing.Add("前 "+count+" 块屏幕需等尺寸、水平相邻");break;}
        var used=new System.Collections.Generic.HashSet<int>();
        for(int i=0;i<count;i++){
            int slot=slots[i];string prefix="玩家 "+(i+1)+"：";
            if(slot==-1){if(i!=0 || mode.SelectedIndex!=1)missing.Add(prefix+"未绑定手柄");else if(checkedParts[i]!=7)missing.Add(prefix+"请点击空白处并按W/A/S/D完成键鼠测试");continue;}
            if(slot<0 || slot>=4 || !connected[slot]){missing.Add(prefix+"手柄未连接");continue;}
            if(!used.Add(slot))missing.Add(prefix+"手柄与其他玩家重复");
            if((checkedParts[i]&1)==0)missing.Add(prefix+"按对应手柄 A 加入");
            
        }
        return string.Join("\r\n",missing.ToArray());
    }
    void WatchGameAndLock() {
        if(Preview)return;
        DateTime now=DateTime.UtcNow;
        if(now>=nextGameCheck){
            nextGameCheck=now.AddSeconds(1);
            gamePids=FindGameProcesses();
            ApplyGameObservation(gamePids.Length>0,now);
        }
        if(now<nextLockCheck)return;nextLockCheck=now.AddMilliseconds(250);
        bool locked=false;
        try{
            string actionPath=Path.Combine(Mod,"four_actions.txt");
            string[] data=File.ReadAllText(actionPath).Split(new char[]{' ','\r','\n'},StringSplitOptions.RemoveEmptyEntries);
            bool fresh=gameStarted && File.GetLastWriteTimeUtc(actionPath)>gameStartUtc;
            if(fresh)fourMode.Checked=true;
            int liveCount;
            if(fresh && data.Length>=7 && int.TryParse(data[6],out liveCount) && liveCount>=2 && liveCount<=4)playerCount.SelectedIndex=liveCount-2;
            locked=fresh && data.Length>=6 && data[1]=="1";
        }catch(IOException){}catch(UnauthorizedAccessException){}catch(ArgumentException){}catch(InvalidOperationException){}
        if(lastLocked && !locked)unlockedUntil=now.AddSeconds(4);
        lastLocked=locked;
        uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);
        bool show=gameStarted && gamePids.Contains((int)pid) && (locked || now<unlockedUntil);
        Screen[] screens=Screen.AllScreens.OrderBy(s=>s.Bounds.Left).ToArray();
        for(int i=0;i<4;i++){
            if(show && i<screens.Length && i<SelectedPlayers){
                if(lockBadges[i]==null || lockBadges[i].IsDisposed)lockBadges[i]=new PartyLockBadge();
                lockBadges[i].Location=new Point(screens[i].Bounds.Left+24,screens[i].Bounds.Top+24);
                lockBadges[i].UpdateState(locked,i);if(!lockBadges[i].Visible)lockBadges[i].Show();
            }else if(lockBadges[i]!=null)lockBadges[i].Hide();
        }
    }
    void WriteBindings() {
        if(!AiStatusReader.MayWriteBindings(Preview,observerOnly,ownsBindings))return;
        // In a running game keep the existing seat assignments usable. The test
        // checklist still gates NEW launches; it must not disable an active seat.
        string value=string.Join("\n",slots.Select((s,i)=>i>=SelectedPlayers?"-1":s==-1?"0":s>=0 && connected[s] && (checkedParts[i]==7 || gameStarted)?(s+1).ToString():"-1").ToArray())+"\n";
        if(value==lastBindings)return;
        string target=Path.Combine(Mod,"four_bindings.txt"), tmp=target+".tmp";
        File.WriteAllText(tmp,value,Encoding.ASCII);
        if(File.Exists(target))File.Replace(tmp,target,null);else File.Move(tmp,target);
        lastBindings=value;
    }
    void StartGame() {
        if(Preview)return;
        try{BaseSwitcher.GuardLaunch(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"BaseVersions"),Mod,StartGameCore);}
        catch(Exception ex){message.Text="启动未完成："+ex.Message;MessageBox.Show(this,ex.Message,"底座检查");}
    }
    void StartGameCore() {
        if(Preview)return;
        try {
            if(launchPending)return;
            if(FindGameProcesses().Length>0){gameStarted=true;EnterReadOnlyObservation();message.Text="已连接当前游戏，仅显示状态；请先退出游戏后重新启动。";return;}
            string problem=ReadinessProblem();
            if(problem.Length>0){message.Text="尚未就绪："+problem.Replace("\r\n","；");MessageBox.Show(this,problem,"请完成这些项目再启动",MessageBoxButtons.OK,MessageBoxIcon.Information);return;}
            observerOnly=false;ownsBindings=true;
            WriteBindings();
            string path=Path.Combine(Mod,"PhantomPact.ini"); string ini=File.ReadAllText(path);
            string input=mode.SelectedIndex==0?"four_pads":"keyboard_three_pads";
            ini=Regex.Replace(ini,@"(?m)^LocalInput\s*=.*$","LocalInput = "+input);
            ini=SetIni(ini,"Role",fourMode.Checked?"Local":"Off");
            ini=SetIni(ini,"LocalPlayers",SelectedPlayers.ToString());
            ini=SetIni(ini,"Monitors",SelectedPlayers.ToString());
            ini=SetIni(ini,"Joysticks","4");
            File.WriteAllText(path,ini,new UTF8Encoding(false));
            Process.Start(new ProcessStartInfo("steam://rungameid/4115450"){UseShellExecute=true});
            launchPending=true;launchDeadline=DateTime.UtcNow.AddSeconds(60);mode.Enabled=false;launch.Text="正在等待游戏启动…";
            message.Text=fourMode.Checked?SelectedPlayers+"人模式已启动；下次默认单人。设置页保持开启。":"已启动单人模式。需要多人时，开启开关并选择人数。";
        }catch(Exception ex){launchPending=false;ownsBindings=false;observerOnly=false;message.Text="启动未完成："+ex.Message;MessageBox.Show(this,ex.Message,"启动失败",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
    static string SetIni(string ini,string key,string value){string pattern=@"(?m)^"+Regex.Escape(key)+@"\s*=.*$";return Regex.IsMatch(ini,pattern)?Regex.Replace(ini,pattern,key+" = "+value):ini+"\r\n"+key+" = "+value+"\r\n";}
    [STAThread] static void Main(string[] args){
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        bool preview=args.Contains("--preview") || args.Contains("--render-preview");
        using(FourPlayerSetup form=new FourPlayerSetup(preview)){
            int render=Array.IndexOf(args,"--render-preview");
            if(render>=0){
                if(render+1>=args.Length)throw new ArgumentException("--render-preview needs an output PNG path");
                form.RenderPreview(Path.GetFullPath(args[render+1]));return;
            }
            Application.Run(form);
        }
    }
}





