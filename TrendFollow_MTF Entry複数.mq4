//+------------------------------------------------------------------+
//|  Trend Follow [5m Double Support Ver] with TP/SL + MTF           |
//|  Pine Script v6 → MQL4 移植版 + マルチタイムフレーム拡張          |
//|  Original logic by original Pine Script author                   |
//+------------------------------------------------------------------+
#property copyright "Ported from Pine Script + MTF"
#property link      ""
#property version   "4.00"
#property strict
#property indicator_chart_window

// ========== 描画バッファ数 ==========
// 0: 買い矢印, 1: 売り矢印, 2: EMA200, 3: EMA365, 4: EMA75, 5: ATR(非表示)
#property indicator_buffers 6
#property indicator_color1  clrGreen
#property indicator_color2  clrRed
#property indicator_color3  clrBlue
#property indicator_color4  clrPurple
#property indicator_color5  clrOrange
#property indicator_color6  clrNONE

// バッファ宣言
double BuyArrowBuffer[];
double SellArrowBuffer[];
double EMA200Buffer[];
double EMA365Buffer[];
double EMA75Buffer[];
double ATRBuffer[];

// ========== 入力パラメーター ==========

// --- 1. MAフィルター ---
input bool   Use_MA_Filter       = true;   // 【方向判定】MAフィルターを使う
input int    MA_Len_Up_Main      = 200;    // 上昇トレンド基準1 (EMA 200)
input int    MA_Len_Up_Deep      = 365;    // 上昇トレンド深い押し目 (EMA 365)
input int    MA_Len_Down         = 75;     // 下落トレンド基準 (EMA 75)

// --- 2. ストキャスティクス ---
input bool   Use_Stoch_Filter    = true;   // 【押し目判定】ストキャスティクスを使う
input int    Stoch_K             = 14;     // K期間
input int    Stoch_D             = 3;      // D期間
input int    Stoch_Smooth        = 3;      // スムージング
input int    Stoch_Upper         = 80;     // 上ライン
input int    Stoch_Lower         = 20;     // 下ライン

// --- 3. RSI角度 ---
input bool   Use_RSI_Angle_Filter = true; // 【勢い判定】RSI角度フィルターを使う
input int    RSI_Length          = 8;      // RSI期間
input int    RSI_Angle_Threshold = 45;     // 最低角度 (度)
input double RSI_Scaling         = 1.0;   // RSI角度補正倍率

// --- 4. 接近判定 ---
input bool   Use_Dist_Filter     = true;  // 【接近判定】MAから離れすぎたら見送る
input double Max_Deviation       = 0.2;   // MAからの最大乖離率(%)

// --- 5. ATRフィルター ---
input bool   Use_ATR_Filter      = true;  // 【値幅判定】ATRフィルター
input int    ATR_Len             = 14;    // ATR期間
input double ATR_Lim_5m         = 5.0;   // ATR下限 (pips) (5分足)
input double ATR_Lim_Default    = 5.0;   // ATR下限 (pips) (その他)

// --- 6. クールダウン ---
input int    Cooldown_Bars       = 5;     // シグナル後の待機本数
input double Arrow_Offset_ATR   = 0.5;   // 矢印のローソク足からの距離（ATR倍率）

// --- 7. TP/SL設定 ---
input bool   Show_TPSL          = true;   // TP/SLラインを表示
input double RR_Ratio           = 2.0;    // リスクリワード比
input double TP1_Percent        = 50.0;   // TP1割合(%)
input double ATR_Multiplier     = 1.5;    // ATR倍率（SL計算用）

// --- 8. レイヤード・エントリー設定 ---
input string Layered_Section    = "=== レイヤード・エントリー設定 ==="; // ──────────────
input bool   Show_Layered       = true;   // 分割エントリーラインを表示
input int    Entry_Splits       = 3;      // 分割数 (2〜4)
input int    Layer_Spacing_Type = 0;      // 間隔タイプ: 0=SL距離の均等割り, 1=固定pips
input double Layer_Fixed_Pips   = 5.0;   // 固定pips間隔 (タイプ1のみ)
input int    Lot_Distribution   = 0;      // ロット配分: 0=均等, 1=SLに近いほど増量

// --- 8. MTF設定 ---
input string MTF_Section        = "=== マルチタイムフレーム設定 ==="; // ──────────────
input bool   Watch_M5           = true;   // M5を監視（5分足シグナルON/OFF）
input bool   Watch_M15          = true;   // M15を監視
input bool   Watch_M30          = true;   // M30を監視
input bool   Watch_H1           = true;   // H1を監視
input int    HTF_Scan_Bars      = 100;    // 上位足スキャン範囲（バー数）

// ========== グローバル変数 ==========
int      g_last_signal_bar  = -9999;
int      g_last_alert_bar   = -9999;
bool     g_has_tpsl         = false;
double   g_saved_sl         = 0.0;
double   g_saved_tp1        = 0.0;
double   g_saved_tp2        = 0.0;
datetime g_saved_tpsl_time  = 0;
// レイヤード・エントリー保存用
double   g_saved_entry      = 0.0;   // 直近エントリー価格
bool     g_saved_is_buy     = false; // 直近シグナル方向

// MTF用グローバル
int      g_htf_last_sig[3];         // 上位足クールダウン用
datetime g_htf_last_alerted[3];     // 上位足アラート重複防止
int      g_htf_label_cnt = 0;       // ラベル通し番号

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    // バッファ0: 買い矢印（↑ Wingdings #233）
    SetIndexBuffer(0, BuyArrowBuffer);
    SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, clrGreen);
    SetIndexArrow(0, 233);
    SetIndexLabel(0, "Buy Signal");
    SetIndexEmptyValue(0, 0.0);

    // バッファ1: 売り矢印（↓ Wingdings #234）
    SetIndexBuffer(1, SellArrowBuffer);
    SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, clrRed);
    SetIndexArrow(1, 234);
    SetIndexLabel(1, "Sell Signal");
    SetIndexEmptyValue(1, 0.0);

    // バッファ2: EMA200（青）
    SetIndexBuffer(2, EMA200Buffer);
    SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 2, clrBlue);
    SetIndexLabel(2, "EMA200");

    // バッファ3: EMA365（紫）
    SetIndexBuffer(3, EMA365Buffer);
    SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, 2, clrPurple);
    SetIndexLabel(3, "EMA365");

    // バッファ4: EMA75（オレンジ）
    SetIndexBuffer(4, EMA75Buffer);
    SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 2, clrOrange);
    SetIndexLabel(4, "EMA75");

    // バッファ5: ATR（非表示・デバッグ用）
    SetIndexBuffer(5, ATRBuffer);
    SetIndexStyle(5, DRAW_NONE);
    SetIndexLabel(5, "ATR(pips)");

    // インジケーター名
    IndicatorShortName("TrendFollow 5m DoubleSupport MTF");

    // MTF初期化
    for(int i = 0; i < 3; i++)
    {
        g_htf_last_sig[i]     = -9999;
        g_htf_last_alerted[i] = 0;
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| チャートから削除されたときの後処理                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, "TPSL_");
    ObjectsDeleteAll(0, "LAYER_");  // レイヤード・エントリー
    ObjectsDeleteAll(0, "HTF_");
    ObjectsDeleteAll(0, "MTFP_");
}

//+------------------------------------------------------------------+
//| ストキャスティクスのスムーズK取得                                  |
//|  Pine: ta.sma(ta.stoch(close,high,low,K), smooth)                |
//|  MT4: iStochastic の MODE_MAIN = スムーズ%K に相当               |
//+------------------------------------------------------------------+
double GetSmoothK(int shift)
{
    return iStochastic(NULL, 0, Stoch_K, Stoch_Smooth, Stoch_D, MODE_SMA, 0, MODE_MAIN, shift);
}

//+------------------------------------------------------------------+
//| RSI角度（度）を計算                                               |
//|  Pine: math.todegrees(math.atan((rsi - rsi[1]) * scaling))      |
//+------------------------------------------------------------------+
double GetRSIAngle(int shift)
{
    double r0 = iRSI(NULL, 0, RSI_Length, PRICE_CLOSE, shift);
    double r1 = iRSI(NULL, 0, RSI_Length, PRICE_CLOSE, shift + 1);
    double delta = (r0 - r1) * RSI_Scaling;
    return MathArctan(delta) * (180.0 / M_PI);
}

//+------------------------------------------------------------------+
//| ATR値をpipsに変換                                                 |
//|  FX 5桁業者: Point=0.00001 → pip=Point×10=0.0001               |
//|  FX 3桁業者: Point=0.001   → pip=Point×10=0.01（JPY系）         |
//|  その他:     pip=Point                                           |
//+------------------------------------------------------------------+
double GetATR_Pips(int shift)
{
    double atr_raw = iATR(NULL, 0, ATR_Len, shift);
    double pip_size = (Digits == 5 || Digits == 3) ? Point * 10.0 : Point;
    return (pip_size > 0) ? atr_raw / pip_size : 0.0;
}

//+------------------------------------------------------------------+
//| TP/SLオブジェクト描画                                             |
//| t_start: ラインの開始時刻（シグナル発生バーの時刻）              |
//+------------------------------------------------------------------+
void DrawTPSL(datetime t_start, double sl, double tp1, double tp2)
{
    // 既存オブジェクトを削除してから再描画
    ObjectsDeleteAll(0, "TPSL_");
    if(!Show_TPSL) return;

    // t2 = シグナル発生時刻 + 12本分
    datetime t2      = t_start + (datetime)(30 * PeriodSeconds());
    datetime t_label = t2 + (datetime)(1 * PeriodSeconds()); // ラベルはライン右端のすぐ右

    color cl_sl  = clrRed;
    color cl_tp1 = clrGreen;
    color cl_tp2 = clrLime;

    // SLライン（現在足まで伸びる固定長）
    ObjectCreate(0, "TPSL_SL", OBJ_TREND, 0, t_start, sl, t2, sl);
    ObjectSet("TPSL_SL", OBJPROP_COLOR, cl_sl);
    ObjectSet("TPSL_SL", OBJPROP_WIDTH, 2);
    ObjectSet("TPSL_SL", OBJPROP_STYLE, STYLE_DASH);
    ObjectSet("TPSL_SL", OBJPROP_RAY_RIGHT, false);

    // TP1ライン（現在足まで伸びる固定長）
    ObjectCreate(0, "TPSL_TP1", OBJ_TREND, 0, t_start, tp1, t2, tp1);
    ObjectSet("TPSL_TP1", OBJPROP_COLOR, cl_tp1);
    ObjectSet("TPSL_TP1", OBJPROP_WIDTH, 2);
    ObjectSet("TPSL_TP1", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet("TPSL_TP1", OBJPROP_RAY_RIGHT, false);

    // TP2ライン（現在足まで伸びる固定長）
    ObjectCreate(0, "TPSL_TP2", OBJ_TREND, 0, t_start, tp2, t2, tp2);
    ObjectSet("TPSL_TP2", OBJPROP_COLOR, cl_tp2);
    ObjectSet("TPSL_TP2", OBJPROP_WIDTH, 2);
    ObjectSet("TPSL_TP2", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet("TPSL_TP2", OBJPROP_RAY_RIGHT, false);
    ObjectCreate(0, "TPSL_SL_LBL",  OBJ_TEXT, 0, t_label, sl);
    ObjectSetString(0, "TPSL_SL_LBL",  OBJPROP_TEXT, "SL");
    ObjectSet("TPSL_SL_LBL",  OBJPROP_COLOR, cl_sl);
    ObjectSet("TPSL_SL_LBL",  OBJPROP_FONTSIZE, 9);

    ObjectCreate(0, "TPSL_TP1_LBL", OBJ_TEXT, 0, t_label, tp1);
    ObjectSetString(0, "TPSL_TP1_LBL", OBJPROP_TEXT,
                   "TP1 (" + IntegerToString((int)TP1_Percent) + "%)");
    ObjectSet("TPSL_TP1_LBL", OBJPROP_COLOR, cl_tp1);
    ObjectSet("TPSL_TP1_LBL", OBJPROP_FONTSIZE, 9);

    ObjectCreate(0, "TPSL_TP2_LBL", OBJ_TEXT, 0, t_label, tp2);
    ObjectSetString(0, "TPSL_TP2_LBL", OBJPROP_TEXT, "TP2 (100%)");
    ObjectSet("TPSL_TP2_LBL", OBJPROP_COLOR, cl_tp2);
    ObjectSet("TPSL_TP2_LBL", OBJPROP_FONTSIZE, 9);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| レイヤード・エントリーライン描画                                   |
//| entry: 第1エントリー価格（成行）                                   |
//| sl:    損切りライン                                                |
//| is_buy: true=買い, false=売り                                      |
//+------------------------------------------------------------------+
void DrawLayeredEntry(datetime t_start, double entry, double sl, bool is_buy)
{
    ObjectsDeleteAll(0, "LAYER_");
    if(!Show_Layered) return;

    int splits = MathMax(2, MathMin(4, Entry_Splits)); // 2〜4に制限
    double pip_size = (Digits == 5 || Digits == 3) ? Point * 10.0 : Point;

    double total_dist = MathAbs(entry - sl);
    if(total_dist <= 0) return;

    datetime t2 = t_start + (datetime)(20 * PeriodSeconds());
    datetime tl = t2 + (datetime)(1 * PeriodSeconds());

    // ロット比率の計算
    // Lot_Distribution=0: 均等 [1,1,1,1]
    // Lot_Distribution=1: SLに近いほど増量 [1,2,3,4]比率
    double lot_weights[];
    ArrayResize(lot_weights, splits);
    double weight_sum = 0;
    for(int i = 0; i < splits; i++)
    {
        lot_weights[i] = (Lot_Distribution == 1) ? (i + 1) : 1.0;
        weight_sum += lot_weights[i];
    }

    // 第1エントリー（成行）を描画（黄色ライン）
    string n0 = "LAYER_E0";
    ObjectCreate(0, n0, OBJ_TREND, 0, t_start, entry, t2, entry);
    ObjectSet(n0, OBJPROP_COLOR, clrYellow);
    ObjectSet(n0, OBJPROP_WIDTH, 2);
    ObjectSet(n0, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet(n0, OBJPROP_RAY_RIGHT, false);
    string n0l = "LAYER_E0L";
    double lot0_pct = (lot_weights[0] / weight_sum) * 100.0;
    ObjectCreate(0, n0l, OBJ_TEXT, 0, tl, entry);
    ObjectSetString(0, n0l, OBJPROP_TEXT, "#1 Market (" + DoubleToString(lot0_pct, 0) + "%)");
    ObjectSet(n0l, OBJPROP_COLOR, clrYellow);
    ObjectSet(n0l, OBJPROP_FONTSIZE, 8);

    // 第2〜第N指値エントリーを描画
    for(int i = 1; i < splits; i++)
    {
        double price;
        if(Layer_Spacing_Type == 1)
        {
            // 固定pips間隔
            double step = Layer_Fixed_Pips * pip_size;
            price = is_buy ? (entry - step * i) : (entry + step * i);
        }
        else
        {
            // SL距離の均等割り
            double step = total_dist / splits;
            price = is_buy ? (entry - step * i) : (entry + step * i);
        }

        // SLを超えないように制限
        if(is_buy  && price <= sl) price = sl + pip_size;
        if(!is_buy && price >= sl) price = sl - pip_size;

        string nm  = "LAYER_E" + IntegerToString(i);
        string nml = "LAYER_E" + IntegerToString(i) + "L";

        color cl = (i == 1) ? clrOrange : (i == 2) ? clrDarkOrange : clrOrangeRed;

        ObjectCreate(0, nm, OBJ_TREND, 0, t_start, price, t2, price);
        ObjectSet(nm, OBJPROP_COLOR, cl);
        ObjectSet(nm, OBJPROP_WIDTH, 1);
        ObjectSet(nm, OBJPROP_STYLE, STYLE_DASH);
        ObjectSet(nm, OBJPROP_RAY_RIGHT, false);

        double lot_pct = (lot_weights[i] / weight_sum) * 100.0;
        double pips_from_entry = MathAbs(entry - price) / pip_size;
        ObjectCreate(0, nml, OBJ_TEXT, 0, tl, price);
        ObjectSetString(0, nml, OBJPROP_TEXT,
            "#" + IntegerToString(i + 1) + " Limit (" + DoubleToString(lot_pct, 0) + "%) " +
            DoubleToString(pips_from_entry, 1) + "pips");
        ObjectSet(nml, OBJPROP_COLOR, cl);
        ObjectSet(nml, OBJPROP_FONTSIZE, 8);
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| メイン計算関数                                                     |
//| ★ 以下はオリジナルのOnCalculateをそのままコピー ★               |
//| ★ MTF部分は末尾でHTF_Process()を呼ぶだけ          ★               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // 計算に必要な最低バー数
    int min_bars = MA_Len_Up_Deep + 10;
    if(rates_total < min_bars) return(0);

    // 計算する開始位置（差分計算でCPUを節約）
    // shift=0: 最新バー / shift大: 古いバー
    int start;
    if(prev_calculated == 0)
    {
        start = rates_total - 1 - min_bars;
        g_last_signal_bar = -9999; // 再計算時にクールダウンをリセット
        g_has_tpsl        = false;  // 再計算時にTP/SL状態をリセット
    }
    else
        start = rates_total - prev_calculated;

    if(start < 0) start = 0;
    if(start >= rates_total) start = rates_total - 1;

    // ===== バーごとのループ（古→新の順、shift は大→0） =====
    for(int shift = start; shift >= 0; shift--)
    {
        // ── EMA ──
        double ema200      = iMA(NULL, 0, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, shift);
        double ema365      = iMA(NULL, 0, MA_Len_Up_Deep, 0, MODE_EMA, PRICE_CLOSE, shift);
        double ema75       = iMA(NULL, 0, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, shift);
        double ema200_prev = iMA(NULL, 0, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, shift + 1);
        double ema75_prev  = iMA(NULL, 0, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, shift + 1);

        // EMAバッファに書き込み（チャート描画用）
        EMA200Buffer[shift] = ema200;
        EMA365Buffer[shift] = ema365;
        EMA75Buffer[shift]  = ema75;

        double cls = iClose(NULL, 0, shift);

        // ── ターゲットEMA決定（5分足専用ロジック） ──
        // 5分足かつ終値がEMA200を下回っていたらEMA365を押し目基準にする
        double target_ema_up;
        if(Period() == PERIOD_M5)
            target_ema_up = (cls < ema200) ? ema365 : ema200;
        else
            target_ema_up = ema200;

        // ── 乖離率フィルター ──
        double dist_up   = (target_ema_up > 0) ? MathAbs(cls - target_ema_up) / target_ema_up * 100.0 : 999.0;
        double dist_down = (ema75 > 0)          ? MathAbs(cls - ema75) / ema75 * 100.0 : 999.0;
        bool near_up   = !Use_Dist_Filter || (dist_up   <= Max_Deviation);
        bool near_down = !Use_Dist_Filter || (dist_down <= Max_Deviation);

        // ── ストキャスティクス ──
        double sk0 = GetSmoothK(shift);
        double sk1 = GetSmoothK(shift + 1);
        bool stoch_buy  = !Use_Stoch_Filter ||
                          (sk0 <= Stoch_Lower || (sk1 <= Stoch_Lower && sk0 > Stoch_Lower));
        bool stoch_sell = !Use_Stoch_Filter ||
                          (sk0 >= Stoch_Upper || (sk1 >= Stoch_Upper && sk0 < Stoch_Upper));

        // ── RSI角度 ──
        double angle = GetRSIAngle(shift);
        bool rsi_buy  = !Use_RSI_Angle_Filter || (angle >=  (double)RSI_Angle_Threshold);
        bool rsi_sell = !Use_RSI_Angle_Filter || (angle <= -(double)RSI_Angle_Threshold);

        // ── ATRフィルター ──
        double atr_pips = GetATR_Pips(shift);
        double req_atr  = (Period() == PERIOD_M5) ? ATR_Lim_5m : ATR_Lim_Default;
        bool atr_ok = !Use_ATR_Filter || (atr_pips >= req_atr);
        ATRBuffer[shift] = atr_pips;

        // ── クールダウン ──
        // 現在バーの連番（古→新で 0,1,2,...）
        int bar_idx = rates_total - 1 - shift;
        bool cooldown_ok = (bar_idx - g_last_signal_bar > Cooldown_Bars);

        // ── トレンド判定 ──
        bool uptrend   = (cls > target_ema_up) && (ema200 > ema200_prev);
        bool downtrend = (cls < ema75)         && (ema75  < ema75_prev);

        // ── 最終シグナル判定 ──
        bool buy_sig  = Watch_M5 && uptrend   && near_up   && stoch_buy  && rsi_buy  && atr_ok && cooldown_ok;
        bool sell_sig = Watch_M5 && downtrend && near_down  && stoch_sell && rsi_sell && atr_ok && cooldown_ok;

        // 【修正2】リペイント防止：毎ティック必ずバッファをリセット
        BuyArrowBuffer[shift]  = 0.0;
        SellArrowBuffer[shift] = 0.0;

        // ── 買いシグナル ──
        if(buy_sig)
        {
            double buy_offset = iATR(NULL, 0, ATR_Len, shift) * Arrow_Offset_ATR;
            BuyArrowBuffer[shift] = iLow(NULL, 0, shift) - buy_offset;

            // TP/SL計算（確定足・現在足共通）
            double atr_raw_b = iATR(NULL, 0, ATR_Len, shift);
            double entry_b   = iClose(NULL, 0, shift);
            double sl_b      = entry_b - atr_raw_b * ATR_Multiplier;
            double risk_b    = entry_b - sl_b;
            double tp1_b     = entry_b + risk_b * RR_Ratio * (TP1_Percent / 100.0);
            double tp2_b     = entry_b + risk_b * RR_Ratio;

            if(shift > 0)
            {
                g_last_signal_bar = bar_idx;
                g_saved_sl        = sl_b;
                g_saved_tp1       = tp1_b;
                g_saved_tp2       = tp2_b;
                g_saved_tpsl_time = Time[shift];
                g_saved_entry     = entry_b;
                g_saved_is_buy    = true;
                g_has_tpsl        = true;
                DrawTPSL(Time[shift], sl_b, tp1_b, tp2_b);
                DrawLayeredEntry(Time[shift], entry_b, sl_b, true);
            }
            else
            {
                DrawTPSL(Time[0], sl_b, tp1_b, tp2_b);
                DrawLayeredEntry(Time[0], entry_b, sl_b, true);

                if(bar_idx != g_last_alert_bar)
                {
                    g_last_alert_bar = bar_idx;
                    Alert("[BUY SIGNAL] ", Symbol(), " [M5]  ATR=", DoubleToString(atr_pips, 1),
                          "pips  SL=", DoubleToString(sl_b, Digits),
                          "  TP1=", DoubleToString(tp1_b, Digits),
                          "  TP2=", DoubleToString(tp2_b, Digits));
                    SendNotification("Buy Signal: " + Symbol() + " [M5]" +
                                     " SL=" + DoubleToString(sl_b, Digits) +
                                     " TP2=" + DoubleToString(tp2_b, Digits));
                }
            }
        }
        // ── 売りシグナル ──
        else if(sell_sig)
        {
            double sell_offset = iATR(NULL, 0, ATR_Len, shift) * Arrow_Offset_ATR;
            SellArrowBuffer[shift] = iHigh(NULL, 0, shift) + sell_offset;

            // TP/SL計算（確定足・現在足共通）
            double atr_raw_s = iATR(NULL, 0, ATR_Len, shift);
            double entry_s   = iClose(NULL, 0, shift);
            double sl_s      = entry_s + atr_raw_s * ATR_Multiplier;
            double risk_s    = sl_s - entry_s;
            double tp1_s     = entry_s - risk_s * RR_Ratio * (TP1_Percent / 100.0);
            double tp2_s     = entry_s - risk_s * RR_Ratio;

            if(shift > 0)
            {
                g_last_signal_bar = bar_idx;
                g_saved_sl        = sl_s;
                g_saved_tp1       = tp1_s;
                g_saved_tp2       = tp2_s;
                g_saved_tpsl_time = Time[shift];
                g_saved_entry     = entry_s;
                g_saved_is_buy    = false;
                g_has_tpsl        = true;
                DrawTPSL(Time[shift], sl_s, tp1_s, tp2_s);
                DrawLayeredEntry(Time[shift], entry_s, sl_s, false);
            }
            else
            {
                DrawTPSL(Time[0], sl_s, tp1_s, tp2_s);
                DrawLayeredEntry(Time[0], entry_s, sl_s, false);

                if(bar_idx != g_last_alert_bar)
                {
                    g_last_alert_bar = bar_idx;
                    Alert("[SELL SIGNAL] ", Symbol(), " [M5]  ATR=", DoubleToString(atr_pips, 1),
                          "pips  SL=", DoubleToString(sl_s, Digits),
                          "  TP1=", DoubleToString(tp1_s, Digits),
                          "  TP2=", DoubleToString(tp2_s, Digits));
                    SendNotification("Sell Signal: " + Symbol() + " [M5]" +
                                     " SL=" + DoubleToString(sl_s, Digits) +
                                     " TP2=" + DoubleToString(tp2_s, Digits));
                }
            }
        }
        // ── シグナルなし（現在足のみ）──
        else if(shift == 0)
        {
            if(g_has_tpsl)
            {
                DrawTPSL(g_saved_tpsl_time, g_saved_sl, g_saved_tp1, g_saved_tp2);
                DrawLayeredEntry(g_saved_tpsl_time, g_saved_entry, g_saved_sl, g_saved_is_buy);
            }
            else
            {
                ObjectsDeleteAll(0, "TPSL_");
                ObjectsDeleteAll(0, "LAYER_");
                ChartRedraw();
            }
        }
    } // end for

    // ===== ここからMTF拡張 =====
    HTF_Process(prev_calculated == 0);
    HTF_DrawPanel();

    return(rates_total);
}

//+------------------------------------------------------------------+
//| ★ ここから下はMTF追加機能 ★                                     |
//| オリジナルのコードには一切触れていません                           |
//+------------------------------------------------------------------+

// 上位足の設定を取得するヘルパー
int HTF_GetPeriod(int idx)
{
    if(idx == 0) return PERIOD_M15;
    if(idx == 1) return PERIOD_M30;
    return PERIOD_H1;
}

string HTF_GetName(int idx)
{
    if(idx == 0) return "M15";
    if(idx == 1) return "M30";
    return "H1";
}

bool HTF_IsEnabled(int idx)
{
    if(idx == 0) return Watch_M15;
    if(idx == 1) return Watch_M30;
    return Watch_H1;
}

color HTF_GetColor(int idx)
{
    if(idx == 0) return clrDeepSkyBlue;
    if(idx == 1) return clrGold;
    return clrMagenta;
}

//+------------------------------------------------------------------+
//| 上位足のTP/SL描画                                                  |
//+------------------------------------------------------------------+
void HTF_DrawTPSL(int idx, datetime t_start, double sl, double tp1, double tp2)
{
    string p = "HTF_TPSL_" + HTF_GetName(idx) + "_";
    ObjectsDeleteAll(0, p);
    if(!Show_TPSL) return;

    datetime t2 = t_start + (datetime)(30 * PeriodSeconds());
    datetime tl = t2 + (datetime)(1 * PeriodSeconds());
    color c = HTF_GetColor(idx);
    string nm = HTF_GetName(idx);

    ObjectCreate(0, p+"SL",  OBJ_TREND, 0, t_start, sl,  t2, sl);
    ObjectSet(p+"SL",  OBJPROP_COLOR, clrRed);
    ObjectSet(p+"SL",  OBJPROP_WIDTH, 2);
    ObjectSet(p+"SL",  OBJPROP_STYLE, STYLE_DASH);
    ObjectSet(p+"SL",  OBJPROP_RAY_RIGHT, false);

    ObjectCreate(0, p+"TP1", OBJ_TREND, 0, t_start, tp1, t2, tp1);
    ObjectSet(p+"TP1", OBJPROP_COLOR, c);
    ObjectSet(p+"TP1", OBJPROP_WIDTH, 2);
    ObjectSet(p+"TP1", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet(p+"TP1", OBJPROP_RAY_RIGHT, false);

    ObjectCreate(0, p+"TP2", OBJ_TREND, 0, t_start, tp2, t2, tp2);
    ObjectSet(p+"TP2", OBJPROP_COLOR, c);
    ObjectSet(p+"TP2", OBJPROP_WIDTH, 2);
    ObjectSet(p+"TP2", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet(p+"TP2", OBJPROP_RAY_RIGHT, false);

    ObjectCreate(0, p+"SLL", OBJ_TEXT, 0, tl, sl);
    ObjectSetString(0, p+"SLL", OBJPROP_TEXT, nm+" SL");
    ObjectSet(p+"SLL", OBJPROP_COLOR, clrRed);
    ObjectSet(p+"SLL", OBJPROP_FONTSIZE, 9);

    ObjectCreate(0, p+"T1L", OBJ_TEXT, 0, tl, tp1);
    ObjectSetString(0, p+"T1L", OBJPROP_TEXT, nm+" TP1("+IntegerToString((int)TP1_Percent)+"%)");
    ObjectSet(p+"T1L", OBJPROP_COLOR, c);
    ObjectSet(p+"T1L", OBJPROP_FONTSIZE, 9);

    ObjectCreate(0, p+"T2L", OBJ_TEXT, 0, tl, tp2);
    ObjectSetString(0, p+"T2L", OBJPROP_TEXT, nm+" TP2(100%)");
    ObjectSet(p+"T2L", OBJPROP_COLOR, c);
    ObjectSet(p+"T2L", OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| 上位足のシグナルラベル描画（矢印＋縦線＋テキスト）                 |
//+------------------------------------------------------------------+
void HTF_DrawLabel(int idx, datetime t, double price, bool is_buy)
{
    g_htf_label_cnt++;
    string base = "HTF_LBL_" + IntegerToString(g_htf_label_cnt);
    string nm   = HTF_GetName(idx);
    color  cl   = HTF_GetColor(idx);

    // ① 矢印マーカー（ローソク足のすぐ近くに表示）
    string arrow_name = base + "_ARW";
    ObjectCreate(0, arrow_name, OBJ_ARROW, 0, t, price);
    ObjectSet(arrow_name, OBJPROP_COLOR, cl);
    ObjectSet(arrow_name, OBJPROP_WIDTH, 2);
    // 買い=上向き矢印(233)、売り=下向き矢印(234)
    ObjectSet(arrow_name, OBJPROP_ARROWCODE, is_buy ? 233 : 234);

    // ② テキストラベル（矢印のさらに外側に表示）
    string text_name = base + "_TXT";
    string text = nm + (is_buy ? " BUY" : " SELL");
    // 矢印の外側にテキストを配置（買い=さらに下、売り=さらに上）
    double text_offset = iATR(NULL, 0, ATR_Len, 0) * 0.5;
    double text_price  = is_buy ? (price - text_offset) : (price + text_offset);

    ObjectCreate(0, text_name, OBJ_TEXT, 0, t, text_price);
    ObjectSetString(0, text_name, OBJPROP_TEXT, text);
    ObjectSet(text_name, OBJPROP_COLOR, cl);
    ObjectSet(text_name, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, text_name, OBJPROP_FONT, "Arial Bold");

    // ③ 縦の点線（どのローソク足か一目でわかるように）
    string vline_name = base + "_VLN";
    ObjectCreate(0, vline_name, OBJ_VLINE, 0, t, 0);
    ObjectSet(vline_name, OBJPROP_COLOR, cl);
    ObjectSet(vline_name, OBJPROP_WIDTH, 1);
    ObjectSet(vline_name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSet(vline_name, OBJPROP_BACK, true);  // チャートの背面に表示
    ObjectSet(vline_name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| 上位足のシグナルスキャン メイン処理                                |
//+------------------------------------------------------------------+
void HTF_Process(bool full_recalc)
{
    if(full_recalc)
    {
        g_htf_label_cnt = 0;
        ObjectsDeleteAll(0, "HTF_LBL_");
        ObjectsDeleteAll(0, "HTF_TPSL_");
        for(int i = 0; i < 3; i++)
        {
            g_htf_last_sig[i]     = -9999;
            g_htf_last_alerted[i] = 0;
        }
    }

    for(int idx = 0; idx < 3; idx++)
    {
        if(!HTF_IsEnabled(idx)) continue;
        HTF_ScanOneTimeframe(idx, full_recalc);
    }
}

//+------------------------------------------------------------------+
//| 上位足1つ分のスキャン                                              |
//+------------------------------------------------------------------+
void HTF_ScanOneTimeframe(int idx, bool full_recalc)
{
    int tf = HTF_GetPeriod(idx);
    string tf_name = HTF_GetName(idx);

    int bars = iBars(NULL, tf);
    int need = MA_Len_Up_Deep + 10;
    if(bars < need) return;

    int limit = MathMin(HTF_Scan_Bars, bars - need);
    if(limit < 1) limit = 1;

    // 初回はフルスキャン、以降は確定足1本のみ
    int from = full_recalc ? limit : 1;

    double pip_size = (Digits == 5 || Digits == 3) ? Point * 10.0 : Point;

    // 最新のTP/SL保存用（ループ中に最後に見つかったシグナルが「最新」）
    bool   found_any   = false;
    double last_sl     = 0;
    double last_tp1    = 0;
    double last_tp2    = 0;
    datetime last_time = 0;

    for(int s = from; s >= 1; s--)   // ★ s>=1：確定足のみ（リペイント防止）
    {
        // ── EMA ──
        double ema200  = iMA(NULL, tf, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, s);
        double ema365  = iMA(NULL, tf, MA_Len_Up_Deep, 0, MODE_EMA, PRICE_CLOSE, s);
        double ema75   = iMA(NULL, tf, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, s);
        double ema200p = iMA(NULL, tf, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, s + 1);
        double ema75p  = iMA(NULL, tf, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, s + 1);
        double cls     = iClose(NULL, tf, s);

        // 上位足はEMA200をそのまま使用（ダブルサポートはM5のみ）
        double target = ema200;

        // ── 乖離率 ──
        double d_up   = (target > 0) ? MathAbs(cls - target) / target * 100.0 : 999.0;
        double d_down = (ema75 > 0)  ? MathAbs(cls - ema75)  / ema75  * 100.0 : 999.0;
        bool near_up   = !Use_Dist_Filter || (d_up   <= Max_Deviation);
        bool near_down = !Use_Dist_Filter || (d_down <= Max_Deviation);

        // ── ストキャスティクス ──
        double sk0 = iStochastic(NULL, tf, Stoch_K, Stoch_Smooth, Stoch_D, MODE_SMA, 0, MODE_MAIN, s);
        double sk1 = iStochastic(NULL, tf, Stoch_K, Stoch_Smooth, Stoch_D, MODE_SMA, 0, MODE_MAIN, s + 1);
        bool stoch_buy  = !Use_Stoch_Filter ||
                          (sk0 <= Stoch_Lower || (sk1 <= Stoch_Lower && sk0 > Stoch_Lower));
        bool stoch_sell = !Use_Stoch_Filter ||
                          (sk0 >= Stoch_Upper || (sk1 >= Stoch_Upper && sk0 < Stoch_Upper));

        // ── RSI角度 ──
        double r0 = iRSI(NULL, tf, RSI_Length, PRICE_CLOSE, s);
        double r1 = iRSI(NULL, tf, RSI_Length, PRICE_CLOSE, s + 1);
        double ang = MathArctan((r0 - r1) * RSI_Scaling) * (180.0 / M_PI);
        bool rsi_buy  = !Use_RSI_Angle_Filter || (ang >=  (double)RSI_Angle_Threshold);
        bool rsi_sell = !Use_RSI_Angle_Filter || (ang <= -(double)RSI_Angle_Threshold);

        // ── ATR ──
        double atr_raw = iATR(NULL, tf, ATR_Len, s);
        double atr_pips = (pip_size > 0) ? atr_raw / pip_size : 0.0;
        bool atr_ok = !Use_ATR_Filter || (atr_pips >= ATR_Lim_Default);

        // ── クールダウン ──
        int bar_num = bars - 1 - s;
        bool cd_ok = (bar_num - g_htf_last_sig[idx] > Cooldown_Bars);

        // ── トレンド ──
        bool up   = (cls > target) && (ema200 > ema200p);
        bool down = (cls < ema75)  && (ema75 < ema75p);

        // ── 最終判定 ──
        bool buy  = up   && near_up   && stoch_buy  && rsi_buy  && atr_ok && cd_ok;
        bool sell = down && near_down && stoch_sell && rsi_sell && atr_ok && cd_ok;

        if(!buy && !sell) continue;

        bool is_buy = buy;

        // クールダウン記録
        g_htf_last_sig[idx] = bar_num;

        // TP/SL計算
        double entry = cls;
        double sl_v, tp1_v, tp2_v, risk;
        if(is_buy)
        {
            sl_v  = entry - atr_raw * ATR_Multiplier;
            risk  = entry - sl_v;
            tp1_v = entry + risk * RR_Ratio * (TP1_Percent / 100.0);
            tp2_v = entry + risk * RR_Ratio;
        }
        else
        {
            sl_v  = entry + atr_raw * ATR_Multiplier;
            risk  = sl_v - entry;
            tp1_v = entry - risk * RR_Ratio * (TP1_Percent / 100.0);
            tp2_v = entry - risk * RR_Ratio;
        }

        // チャート上の位置に変換
        datetime htf_time = iTime(NULL, tf, s);
        int cb = iBarShift(NULL, 0, htf_time, false);
        datetime ct = (cb >= 0) ? Time[cb] : htf_time;

        // 保存
        found_any = true;
        last_sl   = sl_v;
        last_tp1  = tp1_v;
        last_tp2  = tp2_v;
        last_time = ct;

        // ラベル描画
        double lp;
        if(cb >= 0)
            lp = is_buy ? (iLow(NULL, 0, cb) - atr_raw * 0.8) : (iHigh(NULL, 0, cb) + atr_raw * 0.8);
        else
            lp = is_buy ? (entry - atr_raw) : (entry + atr_raw);

        HTF_DrawLabel(idx, ct, lp, is_buy);

        // アラート（最新確定足のみ、リアルタイム時のみ）
        if(s == 1 && !full_recalc)
        {
            if(g_htf_last_alerted[idx] != htf_time)
            {
                g_htf_last_alerted[idx] = htf_time;
                string d = is_buy ? "BUY" : "SELL";

                Alert("[", d, " SIGNAL] ", Symbol(), " [", tf_name, "]",
                      "  ATR=", DoubleToString(atr_pips, 1), "pips",
                      "  SL=", DoubleToString(sl_v, Digits),
                      "  TP1=", DoubleToString(tp1_v, Digits),
                      "  TP2=", DoubleToString(tp2_v, Digits));

                SendNotification(d + " Signal: " + Symbol() +
                                 " [" + tf_name + "]" +
                                 " SL=" + DoubleToString(sl_v, Digits) +
                                 " TP2=" + DoubleToString(tp2_v, Digits));
            }
        }
    }

    // 最新のTP/SL描画
    if(found_any)
        HTF_DrawTPSL(idx, last_time, last_sl, last_tp1, last_tp2);
}

//+------------------------------------------------------------------+
//| MTFパネル描画                                                      |
//+------------------------------------------------------------------+
void HTF_DrawPanel()
{
    // 背景
    if(ObjectFind("MTFP_BG") < 0)
    {
        ObjectCreate(0, "MTFP_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSet("MTFP_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSet("MTFP_BG", OBJPROP_XDISTANCE, 15);
        ObjectSet("MTFP_BG", OBJPROP_YDISTANCE, 25);
        ObjectSet("MTFP_BG", OBJPROP_XSIZE, 220);
        ObjectSet("MTFP_BG", OBJPROP_YSIZE, 132);
        ObjectSet("MTFP_BG", OBJPROP_BGCOLOR, C'30,30,40');
        ObjectSet("MTFP_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSet("MTFP_BG", OBJPROP_COLOR, clrDimGray);
        ObjectSet("MTFP_BG", OBJPROP_BACK, false);
        ObjectSet("MTFP_BG", OBJPROP_SELECTABLE, false);
    }

    // タイトル
    if(ObjectFind("MTFP_TTL") < 0)
    {
        ObjectCreate(0, "MTFP_TTL", OBJ_LABEL, 0, 0, 0);
        ObjectSet("MTFP_TTL", OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSet("MTFP_TTL", OBJPROP_XDISTANCE, 20);
        ObjectSet("MTFP_TTL", OBJPROP_YDISTANCE, 30);
        ObjectSetString(0, "MTFP_TTL", OBJPROP_FONT, "Arial Bold");
        ObjectSet("MTFP_TTL", OBJPROP_FONTSIZE, 11);
        ObjectSet("MTFP_TTL", OBJPROP_COLOR, clrWhite);
        ObjectSet("MTFP_TTL", OBJPROP_SELECTABLE, false);
    }
    ObjectSetString(0, "MTFP_TTL", OBJPROP_TEXT, "MTF - " + Symbol());

    // M5行（固定、先頭に表示）
    string rn_m5 = "MTFP_R_M5";
    if(ObjectFind(rn_m5) < 0)
    {
        ObjectCreate(0, rn_m5, OBJ_LABEL, 0, 0, 0);
        ObjectSet(rn_m5, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSet(rn_m5, OBJPROP_XDISTANCE, 25);
        ObjectSet(rn_m5, OBJPROP_YDISTANCE, 52);
        ObjectSetString(0, rn_m5, OBJPROP_FONT, "Consolas");
        ObjectSet(rn_m5, OBJPROP_FONTSIZE, 10);
        ObjectSet(rn_m5, OBJPROP_SELECTABLE, false);
    }
    if(!Watch_M5)
    {
        ObjectSetString(0, rn_m5, OBJPROP_TEXT, "M5  : OFF");
        ObjectSet(rn_m5, OBJPROP_COLOR, clrDimGray);
    }
    else
    {
        // 現在の5分足トレンドを表示
        double m5_ema200  = iMA(NULL, PERIOD_M5, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, 1);
        double m5_ema200p = iMA(NULL, PERIOD_M5, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, 2);
        double m5_ema75   = iMA(NULL, PERIOD_M5, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, 1);
        double m5_ema75p  = iMA(NULL, PERIOD_M5, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, 2);
        double m5_cls     = iClose(NULL, PERIOD_M5, 1);
        bool m5_up   = (m5_cls > m5_ema200) && (m5_ema200 > m5_ema200p);
        bool m5_down = (m5_cls < m5_ema75)  && (m5_ema75  < m5_ema75p);
        if(m5_up)        { ObjectSetString(0, rn_m5, OBJPROP_TEXT, "M5  : UP");   ObjectSet(rn_m5, OBJPROP_COLOR, clrLime); }
        else if(m5_down) { ObjectSetString(0, rn_m5, OBJPROP_TEXT, "M5  : DOWN"); ObjectSet(rn_m5, OBJPROP_COLOR, clrRed); }
        else             { ObjectSetString(0, rn_m5, OBJPROP_TEXT, "M5  : ---");  ObjectSet(rn_m5, OBJPROP_COLOR, clrGray); }
    }

    // 各行（M15/M30/H1）
    for(int i = 0; i < 3; i++)
    {
        string rn = "MTFP_R" + IntegerToString(i);
        if(ObjectFind(rn) < 0)
        {
            ObjectCreate(0, rn, OBJ_LABEL, 0, 0, 0);
            ObjectSet(rn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSet(rn, OBJPROP_XDISTANCE, 25);
            ObjectSet(rn, OBJPROP_YDISTANCE, 74 + i * 22);
            ObjectSetString(0, rn, OBJPROP_FONT, "Consolas");
            ObjectSet(rn, OBJPROP_FONTSIZE, 10);
            ObjectSet(rn, OBJPROP_SELECTABLE, false);
        }

        string nm = HTF_GetName(i);
        if(!HTF_IsEnabled(i))
        {
            ObjectSetString(0, rn, OBJPROP_TEXT, nm + " : OFF");
            ObjectSet(rn, OBJPROP_COLOR, clrDimGray);
            continue;
        }

        int tf = HTF_GetPeriod(i);
        double h_ema200  = iMA(NULL, tf, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, 1);
        double h_ema200p = iMA(NULL, tf, MA_Len_Up_Main, 0, MODE_EMA, PRICE_CLOSE, 2);
        double h_ema75   = iMA(NULL, tf, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, 1);
        double h_ema75p  = iMA(NULL, tf, MA_Len_Down,    0, MODE_EMA, PRICE_CLOSE, 2);
        double h_cls     = iClose(NULL, tf, 1);

        bool h_up   = (h_cls > h_ema200) && (h_ema200 > h_ema200p);
        bool h_down = (h_cls < h_ema75)  && (h_ema75  < h_ema75p);

        if(h_up)
        {
            ObjectSetString(0, rn, OBJPROP_TEXT, nm + " : UP");
            ObjectSet(rn, OBJPROP_COLOR, clrLime);
        }
        else if(h_down)
        {
            ObjectSetString(0, rn, OBJPROP_TEXT, nm + " : DOWN");
            ObjectSet(rn, OBJPROP_COLOR, clrRed);
        }
        else
        {
            ObjectSetString(0, rn, OBJPROP_TEXT, nm + " : ---");
            ObjectSet(rn, OBJPROP_COLOR, clrGray);
        }
    }

    ChartRedraw();
}
//+------------------------------------------------------------------+
