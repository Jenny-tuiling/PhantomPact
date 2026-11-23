using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

partial class FourPlayerSetup {
    TabControl setupTabs;
    FlowLayoutPanel deviceCards;
    Panel launchFooter;
    Button calibrationToggle;
    Control[][] calibrationControls=new Control[4][];
    bool showCalibration;

    Label CompactNote(string text,int x,int y,int width,int height){
        return new Label{Text=text,Location=new Point(x,y),Size=new Size(width,height),ForeColor=Color.Silver};
    }
    void InitializeCompactLayout(Label title,Button skins,Button weapons,Button about){
        // Reparent the existing controls: polling, ownership and request handlers stay intact.
        Panel shortcuts=Controls.OfType<Panel>().Single(p=>p.Controls.OfType<Label>().Any(l=>l.Text.StartsWith("自定义快捷键")));
        Panel power=(Panel)tempPowerButton.Parent;
        SuspendLayout();
        AutoScroll=false;AutoScrollMinSize=Size.Empty;
        MinimumSize=new Size(810,620);
        ClientSize=new Size(Math.Min(1100,Screen.PrimaryScreen.WorkingArea.Width-32),Math.Min(790,Screen.PrimaryScreen.WorkingArea.Height-64));
        Panel header=new Panel{Dock=DockStyle.Top,Height=84,Width=ClientSize.Width};
        header.Controls.Add(title);title.SetBounds(24,12,440,38);title.Font=new Font(Font.FontFamily,20,FontStyle.Bold);
        header.Controls.Add(CompactNote("选人数，绑定设备，开始一起玩。",26,53,420,24));
        header.Controls.Add(skins);header.Controls.Add(weapons);
        skins.Text="选择皮肤";weapons.Text="队友武器";
        skins.SetBounds(ClientSize.Width-282,24,120,36);weapons.SetBounds(ClientSize.Width-152,24,128,36);
        skins.Anchor=weapons.Anchor=AnchorStyles.Top|AnchorStyles.Right;

        setupTabs=new TabControl{Dock=DockStyle.Fill,Padding=new Point(22,10)};
        TabPage devices=new TabPage("设备与启动"),tools=new TabPage("游戏工具"),keys=new TabPage("按键说明");
        foreach(TabPage page in new[]{devices,tools,keys}){
            page.BackColor=BackColor;page.ForeColor=ForeColor;setupTabs.TabPages.Add(page);
        }
        Panel options=new Panel{Dock=DockStyle.Top,Height=134,Width=ClientSize.Width-8};
        FlowLayoutPanel modes=new FlowLayoutPanel{Dock=DockStyle.Top,Height=48,Padding=new Padding(16,8,0,0),WrapContents=false};
        modes.Controls.Add(fourMode);modes.Controls.Add(playerCount);modes.Controls.Add(mode);
        fourMode.Text="开启多人模式";fourMode.Size=new Size(180,30);fourMode.Margin=new Padding(0,0,12,0);
        playerCount.Size=new Size(130,30);playerCount.Margin=new Padding(0,0,18,0);
        mode.Size=new Size(310,30);mode.Margin=Padding.Empty;
        options.Controls.Add(modes);
        options.Controls.Add(CompactNote("直接按手柄 A 加入 · 已绑定的手柄自动保留 · 换手柄时点“更换手柄”",18,53,730,28));
        options.Controls.Add(monitors);monitors.SetBounds(18,91,550,28);
        calibrationToggle=new Button{Text="展开摇杆校准 ▾",FlatStyle=FlatStyle.Flat,ForeColor=Color.Silver,Size=new Size(170,30)};
        calibrationToggle.Visible=false;
        calibrationToggle.Click+=(s,e)=>SetCalibrationExpanded(!showCalibration);
        deviceCards=new FlowLayoutPanel{Dock=DockStyle.Fill,AutoScroll=true,Padding=new Padding(10,0,6,8),WrapContents=true};
        foreach(Panel card in cards){
            int i=Array.IndexOf(cards,card);
            calibrationControls[i]=card.Controls.Cast<Control>().Where(c=>c.Top>=387).ToArray();
            card.Margin=new Padding(6,0,6,12);card.Size=new Size(245,382);
            foreach(Control control in card.Controls){
                if(control.Top==18)control.Top=12;
                else if(control.Top==68)control.Top=57;
                else if(control.Top==105)control.Top=90;
                else if(control.Top==148)control.Top=131;
                else if(control.Top==192)control.Top=173;
                else if(control.Top==285)control.Top=265;
                else if(control.Top==340)control.Top=325;
            }
            deviceCards.Controls.Add(card);
        }
        foreach(Panel card in cards){
            int i=Array.IndexOf(cards,card);
            foreach(Control c in card.Controls)if(!calibrationControls[i].Contains(c) && c.Top>=57)c.Top+=96;
            foreach(Control c in calibrationControls[i])c.Top=c is Button?57:97;
        }
        for(int i=0;i<cards.Length;i++){
            bind[i].SetBounds(16,142,212,34);
            aiCardLabels[i].SetBounds(16,182,215,26);
            details[i].SetBounds(16,212,215,28);
            live[i].SetBounds(16,244,215,34);
            sticks[i].Top=280;tests[i].SetBounds(16,374,215,30);
        }
        SetCalibrationExpanded(true);
        devices.Controls.Add(deviceCards);devices.Controls.Add(options);
        AttachMouseTest(devices);

        tools.AutoScroll=true;
        tools.Controls.Add(CompactNote("需要时再打开这些功能；设备绑定会继续保持。",20,16,720,28));
        aiButton.Visible=false;
        tools.Controls.Add(recoveryButton);recoveryButton.Text="恢复视角 / 安全脱困";recoveryButton.SetBounds(20,58,250,42);
        var chooseBase=new Button{Text="选择底座 / 切回稳定版",Left=290,Top=58,Width=285,Height=42};
        chooseBase.Click+=(s,e)=>ChooseBase();tools.Controls.Add(chooseBase);
        about.Dispose();
        Panel aiPanel=BuildEmbeddedAiPanel();aiPanel.Location=new Point(20,116);tools.Controls.Add(aiPanel);
        tools.Controls.Add(power);power.SetBounds(20,418,680,180);
        foreach(Control c in power.Controls)c.Width=450;
        tempPowerButton.Text="开启无敌 ＋ 10倍伤害";
        tempPowerStatus.SetBounds(12,110,650,30);
        power.Controls.OfType<Label>().Last().SetBounds(12,142,650,30);
        power.Controls.OfType<Label>().Last().Text="全员生效，再点关闭。每次启动游戏默认关闭。";
        keys.AutoScroll=true;keys.Controls.Add(shortcuts);shortcuts.Location=new Point(18,18);

        launchFooter=new Panel{Dock=DockStyle.Bottom,Height=104,Width=ClientSize.Width,BackColor=Color.FromArgb(28,35,46)};
        launchFooter.Controls.Add(activity);activity.SetBounds(20,9,ClientSize.Width-40,25);activity.Font=new Font(Font.FontFamily,10,FontStyle.Bold);activity.AutoEllipsis=true;
        activity.Text="动一动手柄，对应玩家卡片会亮起";activity.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
        launchFooter.Controls.Add(message);message.SetBounds(20,42,ClientSize.Width-330,54);message.AutoEllipsis=true;message.Font=new Font(Font.FontFamily,10);message.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
        message.Text="默认单人。一起玩时，请开启多人模式。";
        launchFooter.Controls.Add(launch);launch.SetBounds(ClientSize.Width-292,42,270,48);launch.Anchor=AnchorStyles.Top|AnchorStyles.Right;launch.Font=new Font(Font.FontFamily,12,FontStyle.Bold);
        Controls.Clear();Controls.Add(setupTabs);Controls.Add(launchFooter);Controls.Add(header);
        StyleButtons(this);
        ResumeLayout(true);
    }
    void SetCalibrationExpanded(bool expanded){
        expanded=true;showCalibration=true;
        calibrationToggle.Text=expanded?"收起摇杆校准 ▴":"展开摇杆校准 ▾";
        for(int i=0;i<cards.Length;i++){
            foreach(Control control in calibrationControls[i])control.Visible=expanded;
            cards[i].Height=416;
        }
    }
    static void StyleButtons(Control parent){
        foreach(Control c in parent.Controls){
            Button b=c as Button;
            if(b!=null){b.UseVisualStyleBackColor=false;b.BackColor=Color.FromArgb(47,83,107);b.ForeColor=Color.White;b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderColor=Color.FromArgb(103,145,164);}
            StyleButtons(c);
        }
    }
    void AttachMouseTest(Control control){
        if(control is Panel || control is TabPage || control is Label || control is StickPreview)control.MouseDown+=RecordMouseTest;
        foreach(Control child in control.Controls)AttachMouseTest(child);
    }
}
