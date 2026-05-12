//+------------------------------------------------------------------+
//|  Trend Follow [5m Double Support Ver] with TP/SL + MTF           |
//|  MQL4 -> MQL5 Migration                                          |
//+------------------------------------------------------------------+
#property copyright "Ported from Pine Script + MTF"
#property link      ""
#property version   "5.00"
#property indicator_chart_window

#property indicator_buffers 6
#property indicator_plots   5

#property indicator_label1  "Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrGreen
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

#property indicator_label2  "Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

#property indicator_label3  "EMA200"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_width3  2

#property indicator_label4  "EMA365"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrPurple
#property indicator_width4  2

#property indicator_label5  "EMA75"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrOrange
#property indicator_width5  2

double BuyArrowBuffer[];
double SellArrowBuffer[];
double EMA200Buffer[];
double EMA365Buffer[];
double EMA75Buffer[];
double ATRBuffer[];

input bool   Use_MA_Filter        = true;
input int    MA_Len_Up_Main       = 200;
input int    MA_Len_Up_Deep       = 365;
input int    MA_Len_Down          = 75;
input bool   Use_Stoch_Filter     = true;
input int    Stoch_K              = 14;
input int    Stoch_D              = 3;
input int    Stoch_Smooth         = 3;
input int    Stoch_Upper          = 80;
input int    Stoch_Lower          = 20;
input bool   Use_RSI_Angle_Filter = true;
input int    RSI_Length           = 8;
input int    RSI_Angle_Threshold  = 45;
input double RSI_Scaling          = 1.0;
input bool   Use_Dist_Filter      = true;
input double Max_Deviation        = 0.2;
input bool   Use_ATR_Filter       = true;
input int    ATR_Len              = 14;
input double ATR_Lim_5m          = 5.0;
input double ATR_Lim_Default     = 5.0;
input int    Cooldown_Bars        = 5;
input double Arrow_Offset_ATR    = 0.5;
input bool   Show_TPSL           = true;
input double RR_Ratio            = 2.0;
input double TP1_Percent         = 50.0;
input double ATR_Multiplier      = 1.5;
input string Layered_Section     = "=== Layered Entry ===";
input bool   Show_Layered        = true;
input int    Entry_Splits        = 3;
input int    Layer_Spacing_Type  = 0;
input double Layer_Fixed_Pips    = 5.0;
input int    Lot_Distribution    = 0;
input string MTF_Section         = "=== MTF Settings ===";
input bool   Watch_M5            = true;
input bool   Watch_M15           = true;
input bool   Watch_M30           = true;
input bool   Watch_H1            = true;
input int    HTF_Scan_Bars       = 100;

int h_ema200 = INVALID_HANDLE;
int h_ema365 = INVALID_HANDLE;
int h_ema75  = INVALID_HANDLE;
int h_stoch  = INVALID_HANDLE;
int h_rsi    = INVALID_HANDLE;
int h_atr    = INVALID_HANDLE;
int h_htf_ema200[3];
int h_htf_ema365[3];
int h_htf_ema75[3];
int h_htf_stoch[3];
int h_htf_rsi[3];
int h_htf_atr[3];

int      g_last_signal_bar = -9999;
int      g_last_alert_bar  = -9999;
bool     g_has_tpsl        = false;
double   g_saved_sl        = 0.0;
double   g_saved_tp1       = 0.0;
double   g_saved_tp2       = 0.0;
datetime g_saved_tpsl_time = 0;
double   g_saved_entry     = 0.0;
bool     g_saved_is_buy    = false;
int      g_htf_last_sig[3];
datetime g_htf_last_alerted[3];
int      g_htf_label_cnt   = 0;

double GetBuf(int handle, int buf_idx, int shift)
{
    double arr[1];
    if(CopyBuffer(handle, buf_idx, shift, 1, arr) != 1) return 0.0;
    return arr[0];
}

double GetClose_TF(ENUM_TIMEFRAMES tf, int shift)
{
    double arr[1];
    if(CopyClose(NULL, tf, shift, 1, arr) != 1) return 0.0;
    return arr[0];
}

double GetHigh_TF(ENUM_TIMEFRAMES tf, int shift)
{
    double arr[1];
    if(CopyHigh(NULL, tf, shift, 1, arr) != 1) return 0.0;
    return arr[0];
}

double GetLow_TF(ENUM_TIMEFRAMES tf, int shift)
{
    double arr[1];
    if(CopyLow(NULL, tf, shift, 1, arr) != 1) return 0.0;
    return arr[0];
}

datetime GetTime_TF(ENUM_TIMEFRAMES tf, int shift)
{
    datetime arr[1];
    if(CopyTime(NULL, tf, shift, 1, arr) != 1) return 0;
    return arr[0];
}

int GetBarShift_M5(datetime t)
{
    return iBarShift(NULL, PERIOD_CURRENT, t, false);
}

double GetSmoothK(int shift)
{
    return GetBuf(h_stoch, 0, shift);
}

double GetRSIAngle(int shift)
{
    double r0 = GetBuf(h_rsi, 0, shift);
    double r1 = GetBuf(h_rsi, 0, shift + 1);
    double delta = (r0 - r1) * RSI_Scaling;
    return MathArctan(delta) * (180.0 / M_PI);
}

double GetATR_Pips(int shift)
{
    double atr_raw = GetBuf(h_atr, 0, shift);
    double pip_size = (_Digits == 5 || _Digits == 3) ? _Point * 10.0 : _Point;
    return (pip_size > 0) ? atr_raw / pip_size : 0.0;
}

int OnInit()
{
    SetIndexBuffer(0, BuyArrowBuffer,  INDICATOR_DATA);
    SetIndexBuffer(1, SellArrowBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, EMA200Buffer,    INDICATOR_DATA);
    SetIndexBuffer(3, EMA365Buffer,    INDICATOR_DATA);
    SetIndexBuffer(4, EMA75Buffer,     INDICATOR_DATA);
    SetIndexBuffer(5, ATRBuffer,       INDICATOR_CALCULATIONS);
    ArraySetAsSeries(BuyArrowBuffer,  true);
    ArraySetAsSeries(SellArrowBuffer, true);
    ArraySetAsSeries(EMA200Buffer,    true);
    ArraySetAsSeries(EMA365Buffer,    true);
    ArraySetAsSeries(EMA75Buffer,     true);
    ArraySetAsSeries(ATRBuffer,       true);
    PlotIndexSetInteger(0, PLOT_ARROW, 233);
    PlotIndexSetInteger(1, PLOT_ARROW, 234);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    IndicatorSetString(INDICATOR_SHORTNAME, "TrendFollow 5m DoubleSupport MTF");

    h_ema200 = iMA(NULL, PERIOD_CURRENT, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE);
    h_ema365 = iMA(NULL, PERIOD_CURRENT, MA_Len_Up_Deep, 0, MODE_EMA, PRICE_CLOSE);
    h_ema75  = iMA(NULL, PERIOD_CURRENT, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE);
    h_stoch  = iStochastic(NULL, PERIOD_CURRENT, Stoch_K, Stoch_Smooth, Stoch_D, MODE_SMA, STO_LOWHIGH);
    h_rsi    = iRSI(NULL, PERIOD_CURRENT, RSI_Length, PRICE_CLOSE);
    h_atr    = iATR(NULL, PERIOD_CURRENT, ATR_Len);
    if(h_ema200==INVALID_HANDLE||h_ema365==INVALID_HANDLE||h_ema75==INVALID_HANDLE||
       h_stoch==INVALID_HANDLE||h_rsi==INVALID_HANDLE||h_atr==INVALID_HANDLE)
    { Print("Handle error (current TF)"); return INIT_FAILED; }

    ENUM_TIMEFRAMES htf_tfs[3] = {PERIOD_M15, PERIOD_M30, PERIOD_H1};
    for(int i = 0; i < 3; i++)
    {
        h_htf_ema200[i] = iMA(NULL, htf_tfs[i], MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE);
        h_htf_ema365[i] = iMA(NULL, htf_tfs[i], MA_Len_Up_Deep, 0, MODE_EMA, PRICE_CLOSE);
        h_htf_ema75[i]  = iMA(NULL, htf_tfs[i], MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE);
        h_htf_stoch[i]  = iStochastic(NULL, htf_tfs[i], Stoch_K, Stoch_Smooth, Stoch_D, MODE_SMA, STO_LOWHIGH);
        h_htf_rsi[i]    = iRSI(NULL, htf_tfs[i], RSI_Length, PRICE_CLOSE);
        h_htf_atr[i]    = iATR(NULL, htf_tfs[i], ATR_Len);
        if(h_htf_ema200[i]==INVALID_HANDLE||h_htf_ema365[i]==INVALID_HANDLE||h_htf_ema75[i]==INVALID_HANDLE||
           h_htf_stoch[i]==INVALID_HANDLE||h_htf_rsi[i]==INVALID_HANDLE||h_htf_atr[i]==INVALID_HANDLE)
        { Print("Handle error HTF idx=",i); return INIT_FAILED; }
    }
    for(int i = 0; i < 3; i++) { g_htf_last_sig[i] = -9999; g_htf_last_alerted[i] = 0; }
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorRelease(h_ema200); IndicatorRelease(h_ema365); IndicatorRelease(h_ema75);
    IndicatorRelease(h_stoch);  IndicatorRelease(h_rsi);    IndicatorRelease(h_atr);
    for(int i = 0; i < 3; i++)
    {
        IndicatorRelease(h_htf_ema200[i]); IndicatorRelease(h_htf_ema365[i]);
        IndicatorRelease(h_htf_ema75[i]);  IndicatorRelease(h_htf_stoch[i]);
        IndicatorRelease(h_htf_rsi[i]);    IndicatorRelease(h_htf_atr[i]);
    }
    ObjectsDeleteAll(0, "TPSL_");
    ObjectsDeleteAll(0, "LAYER_");
    ObjectsDeleteAll(0, "HTF_");
    ObjectsDeleteAll(0, "MTFP_");
}
void DrawTPSL(datetime t_start, double sl, double tp1, double tp2)
{
    ObjectsDeleteAll(0, "TPSL_");
    if(!Show_TPSL) return;
    datetime t2 = t_start + (datetime)(30 * PeriodSeconds());
    datetime tl = t2 + (datetime)(PeriodSeconds());

    ObjectCreate(0,"TPSL_SL",OBJ_TREND,0,t_start,sl,t2,sl);
    ObjectSetInteger(0,"TPSL_SL",OBJPROP_COLOR,clrRed);
    ObjectSetInteger(0,"TPSL_SL",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,"TPSL_SL",OBJPROP_STYLE,STYLE_DASH);
    ObjectSetInteger(0,"TPSL_SL",OBJPROP_RAY_RIGHT,false);

    ObjectCreate(0,"TPSL_TP1",OBJ_TREND,0,t_start,tp1,t2,tp1);
    ObjectSetInteger(0,"TPSL_TP1",OBJPROP_COLOR,clrGreen);
    ObjectSetInteger(0,"TPSL_TP1",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,"TPSL_TP1",OBJPROP_STYLE,STYLE_SOLID);
    ObjectSetInteger(0,"TPSL_TP1",OBJPROP_RAY_RIGHT,false);

    ObjectCreate(0,"TPSL_TP2",OBJ_TREND,0,t_start,tp2,t2,tp2);
    ObjectSetInteger(0,"TPSL_TP2",OBJPROP_COLOR,clrLime);
    ObjectSetInteger(0,"TPSL_TP2",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,"TPSL_TP2",OBJPROP_STYLE,STYLE_SOLID);
    ObjectSetInteger(0,"TPSL_TP2",OBJPROP_RAY_RIGHT,false);

    ObjectCreate(0,"TPSL_SL_LBL",OBJ_TEXT,0,tl,sl);
    ObjectSetString(0,"TPSL_SL_LBL",OBJPROP_TEXT,"SL");
    ObjectSetInteger(0,"TPSL_SL_LBL",OBJPROP_COLOR,clrRed);
    ObjectSetInteger(0,"TPSL_SL_LBL",OBJPROP_FONTSIZE,9);

    ObjectCreate(0,"TPSL_TP1_LBL",OBJ_TEXT,0,tl,tp1);
    ObjectSetString(0,"TPSL_TP1_LBL",OBJPROP_TEXT,"TP1 ("+IntegerToString((int)TP1_Percent)+"%)");
    ObjectSetInteger(0,"TPSL_TP1_LBL",OBJPROP_COLOR,clrGreen);
    ObjectSetInteger(0,"TPSL_TP1_LBL",OBJPROP_FONTSIZE,9);

    ObjectCreate(0,"TPSL_TP2_LBL",OBJ_TEXT,0,tl,tp2);
    ObjectSetString(0,"TPSL_TP2_LBL",OBJPROP_TEXT,"TP2 (100%)");
    ObjectSetInteger(0,"TPSL_TP2_LBL",OBJPROP_COLOR,clrLime);
    ObjectSetInteger(0,"TPSL_TP2_LBL",OBJPROP_FONTSIZE,9);
    ChartRedraw();
}

void DrawLayeredEntry(datetime t_start, double entry, double sl, bool is_buy)
{
    ObjectsDeleteAll(0, "LAYER_");
    if(!Show_Layered) return;
    int splits = (int)MathMax(2, MathMin(4, Entry_Splits));
    double pip_size = (_Digits==5||_Digits==3) ? _Point*10.0 : _Point;
    double total_dist = MathAbs(entry - sl);
    if(total_dist <= 0) return;
    datetime t2 = t_start + (datetime)(20 * PeriodSeconds());
    datetime tl = t2 + (datetime)(PeriodSeconds());

    double lot_weights[];
    ArrayResize(lot_weights, splits);
    double weight_sum = 0;
    for(int i = 0; i < splits; i++) { lot_weights[i]=(Lot_Distribution==1)?(i+1):1.0; weight_sum+=lot_weights[i]; }

    string n0="LAYER_E0";
    ObjectCreate(0,n0,OBJ_TREND,0,t_start,entry,t2,entry);
    ObjectSetInteger(0,n0,OBJPROP_COLOR,clrYellow);
    ObjectSetInteger(0,n0,OBJPROP_WIDTH,2);
    ObjectSetInteger(0,n0,OBJPROP_STYLE,STYLE_SOLID);
    ObjectSetInteger(0,n0,OBJPROP_RAY_RIGHT,false);
    string n0l="LAYER_E0L";
    double lot0_pct=(lot_weights[0]/weight_sum)*100.0;
    ObjectCreate(0,n0l,OBJ_TEXT,0,tl,entry);
    ObjectSetString(0,n0l,OBJPROP_TEXT,"#1 Market ("+DoubleToString(lot0_pct,0)+"%)");
    ObjectSetInteger(0,n0l,OBJPROP_COLOR,clrYellow);
    ObjectSetInteger(0,n0l,OBJPROP_FONTSIZE,8);

    for(int i = 1; i < splits; i++)
    {
        double price;
        if(Layer_Spacing_Type==1)
        { double step=Layer_Fixed_Pips*pip_size; price=is_buy?(entry-step*i):(entry+step*i); }
        else
        { double step=total_dist/splits; price=is_buy?(entry-step*i):(entry+step*i); }
        if(is_buy  && price<=sl) price=sl+pip_size;
        if(!is_buy && price>=sl) price=sl-pip_size;

        string nm="LAYER_E"+IntegerToString(i);
        string nml="LAYER_E"+IntegerToString(i)+"L";
        color cl=(i==1)?clrOrange:(i==2)?clrDarkOrange:clrOrangeRed;
        ObjectCreate(0,nm,OBJ_TREND,0,t_start,price,t2,price);
        ObjectSetInteger(0,nm,OBJPROP_COLOR,cl);
        ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
        ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DASH);
        ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
        double lot_pct=(lot_weights[i]/weight_sum)*100.0;
        double pips_from_entry=MathAbs(entry-price)/pip_size;
        ObjectCreate(0,nml,OBJ_TEXT,0,tl,price);
        ObjectSetString(0,nml,OBJPROP_TEXT,"#"+IntegerToString(i+1)+" Limit ("+DoubleToString(lot_pct,0)+"%) "+DoubleToString(pips_from_entry,1)+"pips");
        ObjectSetInteger(0,nml,OBJPROP_COLOR,cl);
        ObjectSetInteger(0,nml,OBJPROP_FONTSIZE,8);
    }
    ChartRedraw();
}
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
    ArraySetAsSeries(time,  true); ArraySetAsSeries(open,  true);
    ArraySetAsSeries(high,  true); ArraySetAsSeries(low,   true);
    ArraySetAsSeries(close, true);

    int min_bars = MA_Len_Up_Deep + 10;
    if(rates_total < min_bars) return 0;

    // データが全て揃っているかチェック（シグナル消失・リペイント防止）
    if(BarsCalculated(h_ema200) < rates_total ||
       BarsCalculated(h_ema365) < rates_total ||
       BarsCalculated(h_ema75)  < rates_total ||
       BarsCalculated(h_stoch)  < rates_total ||
       BarsCalculated(h_rsi)    < rates_total ||
       BarsCalculated(h_atr)    < rates_total)
    {
        return 0;
    }

    int start;
    if(prev_calculated == 0)
    {
        start = rates_total - 1 - min_bars;
        g_last_signal_bar = -9999;
        g_has_tpsl        = false;
    }
    else start = rates_total - prev_calculated;
    if(start < 0) start = 0;
    if(start >= rates_total) start = rates_total - 1;

    for(int shift = start; shift >= 0; shift--)
    {
        double ema200      = GetBuf(h_ema200, 0, shift);
        double ema365      = GetBuf(h_ema365, 0, shift);
        double ema75       = GetBuf(h_ema75,  0, shift);
        double ema200_prev = GetBuf(h_ema200, 0, shift + 1);
        double ema75_prev  = GetBuf(h_ema75,  0, shift + 1);

        EMA200Buffer[shift] = ema200;
        EMA365Buffer[shift] = ema365;
        EMA75Buffer[shift]  = ema75;

        double cls = close[shift];

        double target_ema_up;
        if(Period() == PERIOD_M5)
            target_ema_up = (cls < ema200) ? ema365 : ema200;
        else
            target_ema_up = ema200;

        double dist_up   = (target_ema_up > 0) ? MathAbs(cls - target_ema_up) / target_ema_up * 100.0 : 999.0;
        double dist_down = (ema75 > 0) ? MathAbs(cls - ema75) / ema75 * 100.0 : 999.0;
        bool near_up   = !Use_Dist_Filter || (dist_up   <= Max_Deviation);
        bool near_down = !Use_Dist_Filter || (dist_down <= Max_Deviation);

        double sk0 = GetSmoothK(shift);
        double sk1 = GetSmoothK(shift + 1);
        bool stoch_buy  = !Use_Stoch_Filter || (sk0 <= Stoch_Lower || (sk1 <= Stoch_Lower && sk0 > Stoch_Lower));
        bool stoch_sell = !Use_Stoch_Filter || (sk0 >= Stoch_Upper || (sk1 >= Stoch_Upper && sk0 < Stoch_Upper));

        double angle = GetRSIAngle(shift);
        bool rsi_buy  = !Use_RSI_Angle_Filter || (angle >=  (double)RSI_Angle_Threshold);
        bool rsi_sell = !Use_RSI_Angle_Filter || (angle <= -(double)RSI_Angle_Threshold);

        double atr_pips = GetATR_Pips(shift);
        double req_atr  = (Period() == PERIOD_M5) ? ATR_Lim_5m : ATR_Lim_Default;
        bool atr_ok = !Use_ATR_Filter || (atr_pips >= req_atr);
        ATRBuffer[shift] = atr_pips;

        int bar_idx = rates_total - 1 - shift;
        bool cooldown_ok = (bar_idx - g_last_signal_bar > Cooldown_Bars);

        bool uptrend   = (cls > target_ema_up) && (ema200 > ema200_prev);
        bool downtrend = (cls < ema75)         && (ema75  < ema75_prev);

        bool buy_sig  = Watch_M5 && uptrend   && near_up   && stoch_buy  && rsi_buy  && atr_ok && cooldown_ok;
        bool sell_sig = Watch_M5 && downtrend && near_down && stoch_sell && rsi_sell && atr_ok && cooldown_ok;

        BuyArrowBuffer[shift]  = 0.0;
        SellArrowBuffer[shift] = 0.0;

        if(buy_sig)
        {
            double atr_raw_b = GetBuf(h_atr, 0, shift);
            double buy_offset = atr_raw_b * Arrow_Offset_ATR;
            BuyArrowBuffer[shift] = low[shift] - buy_offset;
            double entry_b = close[shift];
            double sl_b    = entry_b - atr_raw_b * ATR_Multiplier;
            double risk_b  = entry_b - sl_b;
            double tp1_b   = entry_b + risk_b * RR_Ratio * (TP1_Percent / 100.0);
            double tp2_b   = entry_b + risk_b * RR_Ratio;
            if(shift > 0)
            {
                g_last_signal_bar = bar_idx;
                g_saved_sl        = sl_b; g_saved_tp1 = tp1_b; g_saved_tp2 = tp2_b;
                g_saved_tpsl_time = time[shift]; g_saved_entry = entry_b; g_saved_is_buy = true;
                g_has_tpsl        = true;
                DrawTPSL(time[shift], sl_b, tp1_b, tp2_b);
                DrawLayeredEntry(time[shift], entry_b, sl_b, true);
            }
            else
            {
                DrawTPSL(time[0], sl_b, tp1_b, tp2_b);
                DrawLayeredEntry(time[0], entry_b, sl_b, true);
                if(bar_idx != g_last_alert_bar)
                {
                    g_last_alert_bar = bar_idx;
                    Alert("[BUY SIGNAL] ", Symbol(), " [M5]  ATR=", DoubleToString(atr_pips,1), "pips  SL=", DoubleToString(sl_b,_Digits), "  TP1=", DoubleToString(tp1_b,_Digits), "  TP2=", DoubleToString(tp2_b,_Digits));
                    SendNotification("Buy Signal: "+Symbol()+" [M5] SL="+DoubleToString(sl_b,_Digits)+" TP2="+DoubleToString(tp2_b,_Digits));
                }
            }
        }
        else if(sell_sig)
        {
            double atr_raw_s = GetBuf(h_atr, 0, shift);
            double sell_offset = atr_raw_s * Arrow_Offset_ATR;
            SellArrowBuffer[shift] = high[shift] + sell_offset;
            double entry_s = close[shift];
            double sl_s    = entry_s + atr_raw_s * ATR_Multiplier;
            double risk_s  = sl_s - entry_s;
            double tp1_s   = entry_s - risk_s * RR_Ratio * (TP1_Percent / 100.0);
            double tp2_s   = entry_s - risk_s * RR_Ratio;
            if(shift > 0)
            {
                g_last_signal_bar = bar_idx;
                g_saved_sl        = sl_s; g_saved_tp1 = tp1_s; g_saved_tp2 = tp2_s;
                g_saved_tpsl_time = time[shift]; g_saved_entry = entry_s; g_saved_is_buy = false;
                g_has_tpsl        = true;
                DrawTPSL(time[shift], sl_s, tp1_s, tp2_s);
                DrawLayeredEntry(time[shift], entry_s, sl_s, false);
            }
            else
            {
                DrawTPSL(time[0], sl_s, tp1_s, tp2_s);
                DrawLayeredEntry(time[0], entry_s, sl_s, false);
                if(bar_idx != g_last_alert_bar)
                {
                    g_last_alert_bar = bar_idx;
                    Alert("[SELL SIGNAL] ", Symbol(), " [M5]  ATR=", DoubleToString(atr_pips,1), "pips  SL=", DoubleToString(sl_s,_Digits), "  TP1=", DoubleToString(tp1_s,_Digits), "  TP2=", DoubleToString(tp2_s,_Digits));
                    SendNotification("Sell Signal: "+Symbol()+" [M5] SL="+DoubleToString(sl_s,_Digits)+" TP2="+DoubleToString(tp2_s,_Digits));
                }
            }
        }
        else if(shift == 0)
        {
            if(g_has_tpsl)
            { DrawTPSL(g_saved_tpsl_time, g_saved_sl, g_saved_tp1, g_saved_tp2); DrawLayeredEntry(g_saved_tpsl_time, g_saved_entry, g_saved_sl, g_saved_is_buy); }
            else
            { ObjectsDeleteAll(0,"TPSL_"); ObjectsDeleteAll(0,"LAYER_"); ChartRedraw(); }
        }
    }

    HTF_Process(prev_calculated == 0);
    HTF_DrawPanel();
    return rates_total;
}
int HTF_GetPeriod(int idx)
{ if(idx==0) return PERIOD_M15; if(idx==1) return PERIOD_M30; return PERIOD_H1; }
string HTF_GetName(int idx)
{ if(idx==0) return "M15"; if(idx==1) return "M30"; return "H1"; }
bool HTF_IsEnabled(int idx)
{ if(idx==0) return Watch_M15; if(idx==1) return Watch_M30; return Watch_H1; }
color HTF_GetColor(int idx)
{ if(idx==0) return clrDeepSkyBlue; if(idx==1) return clrGold; return clrMagenta; }

void HTF_DrawTPSL(int idx, datetime t_start, double sl, double tp1, double tp2)
{
    string p = "HTF_TPSL_" + HTF_GetName(idx) + "_";
    ObjectsDeleteAll(0, p);
    if(!Show_TPSL) return;
    datetime t2 = t_start + (datetime)(30 * PeriodSeconds());
    datetime tl = t2 + (datetime)(PeriodSeconds());
    color c = HTF_GetColor(idx); string nm = HTF_GetName(idx);

    ObjectCreate(0,p+"SL",OBJ_TREND,0,t_start,sl,t2,sl);
    ObjectSetInteger(0,p+"SL",OBJPROP_COLOR,clrRed); ObjectSetInteger(0,p+"SL",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,p+"SL",OBJPROP_STYLE,STYLE_DASH); ObjectSetInteger(0,p+"SL",OBJPROP_RAY_RIGHT,false);
    ObjectCreate(0,p+"TP1",OBJ_TREND,0,t_start,tp1,t2,tp1);
    ObjectSetInteger(0,p+"TP1",OBJPROP_COLOR,c); ObjectSetInteger(0,p+"TP1",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,p+"TP1",OBJPROP_STYLE,STYLE_SOLID); ObjectSetInteger(0,p+"TP1",OBJPROP_RAY_RIGHT,false);
    ObjectCreate(0,p+"TP2",OBJ_TREND,0,t_start,tp2,t2,tp2);
    ObjectSetInteger(0,p+"TP2",OBJPROP_COLOR,c); ObjectSetInteger(0,p+"TP2",OBJPROP_WIDTH,2);
    ObjectSetInteger(0,p+"TP2",OBJPROP_STYLE,STYLE_SOLID); ObjectSetInteger(0,p+"TP2",OBJPROP_RAY_RIGHT,false);
    ObjectCreate(0,p+"SLL",OBJ_TEXT,0,tl,sl);
    ObjectSetString(0,p+"SLL",OBJPROP_TEXT,nm+" SL");
    ObjectSetInteger(0,p+"SLL",OBJPROP_COLOR,clrRed); ObjectSetInteger(0,p+"SLL",OBJPROP_FONTSIZE,9);
    ObjectCreate(0,p+"T1L",OBJ_TEXT,0,tl,tp1);
    ObjectSetString(0,p+"T1L",OBJPROP_TEXT,nm+" TP1("+IntegerToString((int)TP1_Percent)+"%)");
    ObjectSetInteger(0,p+"T1L",OBJPROP_COLOR,c); ObjectSetInteger(0,p+"T1L",OBJPROP_FONTSIZE,9);
    ObjectCreate(0,p+"T2L",OBJ_TEXT,0,tl,tp2);
    ObjectSetString(0,p+"T2L",OBJPROP_TEXT,nm+" TP2(100%)");
    ObjectSetInteger(0,p+"T2L",OBJPROP_COLOR,c); ObjectSetInteger(0,p+"T2L",OBJPROP_FONTSIZE,9);
}

void HTF_DrawLabel(int idx, datetime t, double price, bool is_buy)
{
    g_htf_label_cnt++;
    string base="HTF_LBL_"+IntegerToString(g_htf_label_cnt);
    string nm=HTF_GetName(idx); color cl=HTF_GetColor(idx);

    string arrow_name=base+"_ARW";
    ObjectCreate(0,arrow_name,OBJ_ARROW,0,t,price);
    ObjectSetInteger(0,arrow_name,OBJPROP_COLOR,cl);
    ObjectSetInteger(0,arrow_name,OBJPROP_WIDTH,2);
    ObjectSetInteger(0,arrow_name,OBJPROP_ARROWCODE,is_buy?233:234);

    string text_name=base+"_TXT";
    string text=nm+(is_buy?" BUY":" SELL");
    double text_offset=GetBuf(h_atr,0,0)*0.5;
    double text_price=is_buy?(price-text_offset):(price+text_offset);
    ObjectCreate(0,text_name,OBJ_TEXT,0,t,text_price);
    ObjectSetString(0,text_name,OBJPROP_TEXT,text);
    ObjectSetInteger(0,text_name,OBJPROP_COLOR,cl);
    ObjectSetInteger(0,text_name,OBJPROP_FONTSIZE,9);
    ObjectSetString(0,text_name,OBJPROP_FONT,"Arial Bold");

    string vline_name=base+"_VLN";
    ObjectCreate(0,vline_name,OBJ_VLINE,0,t,0);
    ObjectSetInteger(0,vline_name,OBJPROP_COLOR,cl);
    ObjectSetInteger(0,vline_name,OBJPROP_WIDTH,1);
    ObjectSetInteger(0,vline_name,OBJPROP_STYLE,STYLE_DOT);
    ObjectSetInteger(0,vline_name,OBJPROP_BACK,true);
    ObjectSetInteger(0,vline_name,OBJPROP_SELECTABLE,false);
}

void HTF_Process(bool full_recalc)
{
    if(full_recalc)
    {
        g_htf_label_cnt=0;
        ObjectsDeleteAll(0,"HTF_LBL_"); ObjectsDeleteAll(0,"HTF_TPSL_");
        for(int i=0;i<3;i++){g_htf_last_sig[i]=-9999;g_htf_last_alerted[i]=0;}
    }
    for(int idx=0;idx<3;idx++)
    { if(!HTF_IsEnabled(idx)) continue; HTF_ScanOneTimeframe(idx,full_recalc); }
}

void HTF_ScanOneTimeframe(int idx, bool full_recalc)
{
    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)HTF_GetPeriod(idx);
    string tf_name     = HTF_GetName(idx);
    int bars           = iBars(NULL, tf);
    int need           = MA_Len_Up_Deep + 10;
    if(bars < need) return;
    int limit = (int)MathMin(HTF_Scan_Bars, bars - need);
    if(limit < 1) limit = 1;
    int from = full_recalc ? limit : 1;
    double pip_size = (_Digits==5||_Digits==3) ? _Point*10.0 : _Point;
    bool   found_any=false;
    double last_sl=0,last_tp1=0,last_tp2=0; datetime last_time=0;

    for(int s=from;s>=1;s--)
    {
        double ema200  = GetBuf(h_htf_ema200[idx],0,s);
        double ema365  = GetBuf(h_htf_ema365[idx],0,s);
        double ema75   = GetBuf(h_htf_ema75[idx], 0,s);
        double ema200p = GetBuf(h_htf_ema200[idx],0,s+1);
        double ema75p  = GetBuf(h_htf_ema75[idx], 0,s+1);
        double cls     = GetClose_TF(tf,s);
        double target  = ema200;

        double d_up   = (target>0)?MathAbs(cls-target)/target*100.0:999.0;
        double d_down = (ema75>0)?MathAbs(cls-ema75)/ema75*100.0:999.0;
        bool near_up   = !Use_Dist_Filter||(d_up<=Max_Deviation);
        bool near_down = !Use_Dist_Filter||(d_down<=Max_Deviation);

        double sk0 = GetBuf(h_htf_stoch[idx],0,s);
        double sk1 = GetBuf(h_htf_stoch[idx],0,s+1);
        bool stoch_buy  = !Use_Stoch_Filter||(sk0<=Stoch_Lower||(sk1<=Stoch_Lower&&sk0>Stoch_Lower));
        bool stoch_sell = !Use_Stoch_Filter||(sk0>=Stoch_Upper||(sk1>=Stoch_Upper&&sk0<Stoch_Upper));

        double r0 = GetBuf(h_htf_rsi[idx],0,s);
        double r1 = GetBuf(h_htf_rsi[idx],0,s+1);
        double ang = MathArctan((r0-r1)*RSI_Scaling)*(180.0/M_PI);
        bool rsi_buy  = !Use_RSI_Angle_Filter||(ang>=(double)RSI_Angle_Threshold);
        bool rsi_sell = !Use_RSI_Angle_Filter||(ang<=-(double)RSI_Angle_Threshold);

        double atr_raw  = GetBuf(h_htf_atr[idx],0,s);
        double atr_pips = (pip_size>0)?atr_raw/pip_size:0.0;
        bool atr_ok = !Use_ATR_Filter||(atr_pips>=ATR_Lim_Default);

        int bar_num = bars-1-s;
        bool cd_ok = (bar_num-g_htf_last_sig[idx]>Cooldown_Bars);

        bool up   = (cls>target)&&(ema200>ema200p);
        bool down = (cls<ema75)&&(ema75<ema75p);
        bool buy  = up&&near_up&&stoch_buy&&rsi_buy&&atr_ok&&cd_ok;
        bool sell = down&&near_down&&stoch_sell&&rsi_sell&&atr_ok&&cd_ok;
        if(!buy&&!sell) continue;

        bool is_buy = buy;
        g_htf_last_sig[idx] = bar_num;

        double entry=cls, sl_v, tp1_v, tp2_v, risk;
        if(is_buy){sl_v=entry-atr_raw*ATR_Multiplier;risk=entry-sl_v;tp1_v=entry+risk*RR_Ratio*(TP1_Percent/100.0);tp2_v=entry+risk*RR_Ratio;}
        else       {sl_v=entry+atr_raw*ATR_Multiplier;risk=sl_v-entry;tp1_v=entry-risk*RR_Ratio*(TP1_Percent/100.0);tp2_v=entry-risk*RR_Ratio;}

        datetime htf_time = GetTime_TF(tf, s);
        int cb = GetBarShift_M5(htf_time);
        datetime ct = (cb>=0) ? iTime(NULL,PERIOD_CURRENT,cb) : htf_time;

        found_any=true; last_sl=sl_v; last_tp1=tp1_v; last_tp2=tp2_v; last_time=ct;

        double lp;
        if(cb>=0) lp=is_buy?(GetLow_TF(PERIOD_CURRENT,cb)-atr_raw*0.8):(GetHigh_TF(PERIOD_CURRENT,cb)+atr_raw*0.8);
        else      lp=is_buy?(entry-atr_raw):(entry+atr_raw);
        HTF_DrawLabel(idx,ct,lp,is_buy);

        if(s==1&&!full_recalc&&g_htf_last_alerted[idx]!=htf_time)
        {
            g_htf_last_alerted[idx]=htf_time;
            string d=is_buy?"BUY":"SELL";
            Alert("[",d," SIGNAL] ",Symbol()," [",tf_name,"]  ATR=",DoubleToString(atr_pips,1),"pips  SL=",DoubleToString(sl_v,_Digits),"  TP1=",DoubleToString(tp1_v,_Digits),"  TP2=",DoubleToString(tp2_v,_Digits));
            SendNotification(d+" Signal: "+Symbol()+" ["+tf_name+"] SL="+DoubleToString(sl_v,_Digits)+" TP2="+DoubleToString(tp2_v,_Digits));
        }
    }
    if(found_any) HTF_DrawTPSL(idx,last_time,last_sl,last_tp1,last_tp2);
}
void HTF_DrawPanel()
{
    if(ObjectFind(0,"MTFP_BG")<0)
    {
        ObjectCreate(0,"MTFP_BG",OBJ_RECTANGLE_LABEL,0,0,0);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_XDISTANCE,15);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_YDISTANCE,25);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_XSIZE,220);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_YSIZE,132);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_BGCOLOR,C'30,30,40');
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_BORDER_TYPE,BORDER_FLAT);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_COLOR,clrDimGray);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_BACK,false);
        ObjectSetInteger(0,"MTFP_BG",OBJPROP_SELECTABLE,false);
    }
    if(ObjectFind(0,"MTFP_TTL")<0)
    {
        ObjectCreate(0,"MTFP_TTL",OBJ_LABEL,0,0,0);
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_XDISTANCE,20);
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_YDISTANCE,30);
        ObjectSetString(0,"MTFP_TTL",OBJPROP_FONT,"Arial Bold");
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_FONTSIZE,11);
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_COLOR,clrWhite);
        ObjectSetInteger(0,"MTFP_TTL",OBJPROP_SELECTABLE,false);
    }
    ObjectSetString(0,"MTFP_TTL",OBJPROP_TEXT,"MTF - "+Symbol());

    string rn_m5="MTFP_R_M5";
    if(ObjectFind(0,rn_m5)<0)
    {
        ObjectCreate(0,rn_m5,OBJ_LABEL,0,0,0);
        ObjectSetInteger(0,rn_m5,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,rn_m5,OBJPROP_XDISTANCE,25);
        ObjectSetInteger(0,rn_m5,OBJPROP_YDISTANCE,52);
        ObjectSetString(0,rn_m5,OBJPROP_FONT,"Consolas");
        ObjectSetInteger(0,rn_m5,OBJPROP_FONTSIZE,10);
        ObjectSetInteger(0,rn_m5,OBJPROP_SELECTABLE,false);
    }
    if(!Watch_M5)
    { ObjectSetString(0,rn_m5,OBJPROP_TEXT,"M5  : OFF"); ObjectSetInteger(0,rn_m5,OBJPROP_COLOR,clrDimGray); }
    else
    {
        double m5_ema200  = GetBuf(h_ema200,0,1);
        double m5_ema200p = GetBuf(h_ema200,0,2);
        double m5_ema75   = GetBuf(h_ema75, 0,1);
        double m5_ema75p  = GetBuf(h_ema75, 0,2);
        double m5_cls     = GetClose_TF(PERIOD_CURRENT,1);
        bool m5_up   = (m5_cls>m5_ema200)&&(m5_ema200>m5_ema200p);
        bool m5_down = (m5_cls<m5_ema75)&&(m5_ema75<m5_ema75p);
        if(m5_up)        {ObjectSetString(0,rn_m5,OBJPROP_TEXT,"M5  : UP");   ObjectSetInteger(0,rn_m5,OBJPROP_COLOR,clrLime);}
        else if(m5_down) {ObjectSetString(0,rn_m5,OBJPROP_TEXT,"M5  : DOWN"); ObjectSetInteger(0,rn_m5,OBJPROP_COLOR,clrRed);}
        else             {ObjectSetString(0,rn_m5,OBJPROP_TEXT,"M5  : ---");  ObjectSetInteger(0,rn_m5,OBJPROP_COLOR,clrGray);}
    }

    for(int i=0;i<3;i++)
    {
        string rn="MTFP_R"+IntegerToString(i);
        if(ObjectFind(0,rn)<0)
        {
            ObjectCreate(0,rn,OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,rn,OBJPROP_CORNER,CORNER_LEFT_UPPER);
            ObjectSetInteger(0,rn,OBJPROP_XDISTANCE,25);
            ObjectSetInteger(0,rn,OBJPROP_YDISTANCE,74+i*22);
            ObjectSetString(0,rn,OBJPROP_FONT,"Consolas");
            ObjectSetInteger(0,rn,OBJPROP_FONTSIZE,10);
            ObjectSetInteger(0,rn,OBJPROP_SELECTABLE,false);
        }
        string nm=HTF_GetName(i);
        if(!HTF_IsEnabled(i))
        {ObjectSetString(0,rn,OBJPROP_TEXT,nm+" : OFF"); ObjectSetInteger(0,rn,OBJPROP_COLOR,clrDimGray); continue;}
        ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)HTF_GetPeriod(i);
        double h_ema200v  = GetBuf(h_htf_ema200[i],0,1);
        double h_ema200pv = GetBuf(h_htf_ema200[i],0,2);
        double h_ema75v   = GetBuf(h_htf_ema75[i], 0,1);
        double h_ema75pv  = GetBuf(h_htf_ema75[i], 0,2);
        double h_cls      = GetClose_TF(tf,1);
        bool h_up   = (h_cls>h_ema200v)&&(h_ema200v>h_ema200pv);
        bool h_down = (h_cls<h_ema75v)&&(h_ema75v<h_ema75pv);
        if(h_up)        {ObjectSetString(0,rn,OBJPROP_TEXT,nm+" : UP");   ObjectSetInteger(0,rn,OBJPROP_COLOR,clrLime);}
        else if(h_down) {ObjectSetString(0,rn,OBJPROP_TEXT,nm+" : DOWN"); ObjectSetInteger(0,rn,OBJPROP_COLOR,clrRed);}
        else            {ObjectSetString(0,rn,OBJPROP_TEXT,nm+" : ---");  ObjectSetInteger(0,rn,OBJPROP_COLOR,clrGray);}
    }
    ChartRedraw();
}
//+------------------------------------------------------------------+