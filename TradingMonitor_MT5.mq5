//+------------------------------------------------------------------+
//|                                         TradingMonitor_MT5.mq5  |
//|                         Copyright 2026, Trading Monitor Project  |
//|                                                                  |
//| 概要:                                                             |
//|   裁量トレーダー向け過剰売買防止モニタリングインジケーター               |
//|   NYタイム17:00を1日の区切りとして本日のトレード統計をダッシュボード表示 |
//|   各種アラート条件が設定した閾値に達した際にポップアップ通知を発動         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Trading Monitor Project"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

//============================================================
// ★ ダッシュボード配置設定
//============================================================
input ENUM_BASE_CORNER DashboardCorner    = CORNER_LEFT_UPPER; // ダッシュボード配置コーナー
input int              DashboardOffsetX   = 15;                // X方向オフセット(ピクセル)
input int              DashboardOffsetY   = 15;                // Y方向オフセット(ピクセル)

//============================================================
// ★ NYタイム / サーバー時刻オフセット設定
//   自動計算する場合は 999 のままにしてください
//   手動で指定する場合: サーバー時刻 - NY時刻 の差(時間)を入力
//   例) サーバー = UTC+2、NY = UTC-5(冬時間) → 差 = 7 を入力
//============================================================
input int ServerToNYOffsetHours = 999; // サーバー→NYオフセット(時間)[999=自動]

//============================================================
// ★ アラート1: 損失限度額アラート
//   本日の確定損益がこの損失額に達したらアラート
//============================================================
input bool   Alert1_Enable    = true;         // [損失限度] 有効/無効
input double Alert1_Threshold = -10000.0;     // [損失限度] 閾値(マイナス値で入力)
input string Alert1_Message   = "本日の損失限度額に達しました！トレードを停止してください。"; // [損失限度] メッセージ
input color  Alert1_BoxColor  = clrFireBrick; // [損失限度] ボックス背景色
input color  Alert1_TxtColor  = clrWhite;     // [損失限度] テキスト色

//============================================================
// ★ アラート2: 目標利益額アラート
//   本日の確定損益がこの利益額に達したらアラート
//============================================================
input bool   Alert2_Enable    = true;          // [目標利益] 有効/無効
input double Alert2_Threshold = 20000.0;       // [目標利益] 閾値(プラス値で入力)
input string Alert2_Message   = "本日の目標利益額を達成しました！無理にトレードしないでください。"; // [目標利益] メッセージ
input color  Alert2_BoxColor  = clrDarkGreen;  // [目標利益] ボックス背景色
input color  Alert2_TxtColor  = clrWhite;      // [目標利益] テキスト色

//============================================================
// ★ アラート3: トレード回数アラート
//   本日のトレード回数がこの回数を超えたらアラート
//============================================================
input bool   Alert3_Enable    = true;          // [回数制限] 有効/無効
input int    Alert3_Threshold = 10;            // [回数制限] 閾値(回)
input string Alert3_Message   = "本日のトレード回数が上限を超えました！";    // [回数制限] メッセージ
input color  Alert3_BoxColor  = clrDarkOrange; // [回数制限] ボックス背景色
input color  Alert3_TxtColor  = clrWhite;      // [回数制限] テキスト色

//============================================================
// ★ アラート4: 連勝数アラート
//   連続して勝ちトレードがこの回数に達したらアラート
//============================================================
input bool   Alert4_Enable    = true;        // [連勝] 有効/無効
input int    Alert4_Threshold = 5;           // [連勝] 閾値(回)
input string Alert4_Message   = "連勝中！利益確定のタイミングを慎重に検討してください。"; // [連勝] メッセージ
input color  Alert4_BoxColor  = clrDarkBlue; // [連勝] ボックス背景色
input color  Alert4_TxtColor  = clrWhite;    // [連勝] テキスト色

//============================================================
// ★ アラート5: 連敗数アラート
//   連続して負けトレードがこの回数に達したらアラート
//============================================================
input bool   Alert5_Enable    = true;         // [連敗] 有効/無効
input int    Alert5_Threshold = 3;            // [連敗] 閾値(回)
input string Alert5_Message   = "連敗中！一度休憩してメンタルを整えてください。";  // [連敗] メッセージ
input color  Alert5_BoxColor  = clrDarkRed;   // [連敗] ボックス背景色
input color  Alert5_TxtColor  = clrWhite;     // [連敗] テキスト色

//============================================================
// ★ アラート6: 同時保有ポジション数アラート
//   現在の同時保有ポジション数がこの数を超えたらアラート
//============================================================
input bool   Alert6_Enable    = true;          // [同時保有] 有効/無効
input int    Alert6_Threshold = 3;             // [同時保有] 閾値(ポジション数)
input string Alert6_Message   = "同時保有ポジション数が上限を超えています！";  // [同時保有] メッセージ
input color  Alert6_BoxColor  = clrPurple;     // [同時保有] ボックス背景色
input color  Alert6_TxtColor  = clrWhite;      // [同時保有] テキスト色

//============================================================
// ★ アラート7: ボラティリティアラート
//   本日の高値-安値レンジに基づくアラート
//   Mode: "Rate(%)" = レンジをレート比で判定 / "Price" = レンジを価格差で判定
//   Direction: "Upper" = 上限以上でアラート / "Lower" = 下限以下でアラート
//============================================================
input bool   Alert7_Enable      = true;       // [ボラ] 有効/無効
input double Alert7_Threshold   = 0.5;        // [ボラ] 閾値
input string Alert7_Mode        = "Rate(%)";  // [ボラ] モード: "Rate(%)" or "Price"
input string Alert7_Direction   = "Upper";    // [ボラ] 方向: "Upper" or "Lower"
input string Alert7_Message     = "ボラティリティ条件に達しました！エントリー前に確認してください。"; // [ボラ] メッセージ
input color  Alert7_BoxColor    = clrTeal;    // [ボラ] ボックス背景色
input color  Alert7_TxtColor    = clrWhite;   // [ボラ] テキスト色

//============================================================
// 定数・グローバル変数
//============================================================
#define PANEL_PREFIX      "TM5_"      // チャートオブジェクト名のプレフィックス
#define PANEL_WIDTH       320         // パネル幅(ピクセル)
#define PANEL_FONT        "Meiryo UI" // フォント名(日本語対応)
#define PANEL_FONT_SIZE   9           // 標準フォントサイズ
#define TIMER_INTERVAL_MS 1000        // タイマー更新間隔(ミリ秒)

// ダークテーマ配色
#define CLR_BG          (color)0x1A1A2E   // パネル背景色(ダークネイビー)
#define CLR_HEADER      (color)0x16213E   // ヘッダー背景色
#define CLR_BORDER      (color)0x0F3460   // ボーダー色
#define CLR_TITLE       (color)0xE8D5B7   // タイトルテキスト色
#define CLR_LABEL       (color)0x8892B0   // ラベルテキスト色(グレー)
#define CLR_VALUE       (color)0xCCD6F6   // 値テキスト色(ライトブルー)
#define CLR_GREEN       (color)0x64FFDA   // 良好状態色
#define CLR_YELLOW      (color)0xFFD700   // 注意状態色
#define CLR_RED         (color)0xFF6B6B   // 危険状態色
#define CLR_DIVIDER     (color)0x233554   // 区切り線色
#define CLR_PROFIT      (color)0x64FFDA   // プラス損益色
#define CLR_LOSS        (color)0xFF6B6B   // マイナス損益色

// アラート発動済みフラグ(同日中に1回のみ発動させるため)
bool g_Alert1Fired = false;
bool g_Alert2Fired = false;
bool g_Alert3Fired = false;
bool g_Alert4Fired = false;
bool g_Alert5Fired = false;
bool g_Alert6Fired = false;
bool g_Alert7Fired = false;

// 前回のNYデイスタート時刻(キャッシュ用)
datetime g_LastNYDayStart = 0;

// トレード統計構造体
struct TradeStats
{
   // 損益関連
   double realizedPnL;     // 確定損益
   double unrealizedPnL;   // 未確定損益(フロート)
   double totalPnL;        // 合計損益
   
   // トレード回数
   int    totalTrades;     // 総トレード数
   int    wins;            // 勝ちトレード数
   int    losses;          // 負けトレード数
   int    draws;           // ドロー数
   
   // 勝率・リスクリワード
   double winRate;         // 勝率(%)
   double riskReward;      // リスクリワード比率
   double avgPnL;          // 平均損益
   
   // 利益統計
   double avgProfit;       // 平均利益
   double maxProfit;       // 最大利益
   
   // 損失統計
   double avgLoss;         // 平均損失
   double maxLoss;         // 最大損失(最も大きな損失)
   
   // 保有時間
   double avgHoldSec;      // 平均保有時間(秒)
   double avgWinHoldSec;   // 勝ちトレード平均保有時間(秒)
   double avgLossHoldSec;  // 負けトレード平均保有時間(秒)
   
   // 連勝・連敗
   int    consecWins;      // 現在の連勝数
   int    consecLosses;    // 現在の連敗数
   
   // ボラティリティ
   double todayHigh;       // 本日高値
   double todayLow;        // 本日安値
   double volRange;        // 高値-安値レンジ(価格差)
   double volRangeRate;    // 高値-安値レンジ(レート比%)
   
   // 保有ポジション数
   int    openPositions;   // 現在の保有ポジション数
};

//+------------------------------------------------------------------+
//| OnInit: インジケーター初期化                                        |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1秒ごとのタイマーを設定(ダッシュボード更新用)
   EventSetMillisecondTimer(TIMER_INTERVAL_MS);
   
   // 初期描画
   UpdateDashboard();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit: インジケーター終了処理                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // タイマー停止
   EventKillTimer();
   
   // 作成した全チャートオブジェクトを削除
   DeleteAllPanelObjects();
   
   // チャート再描画
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate: ティックごとの計算(ここでは使用しない)                  |
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
   return(rates_total);
}

//+------------------------------------------------------------------+
//| OnTick: ティック更新時の処理                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // ティックごとにもダッシュボードを更新(リアルタイム性向上)
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| OnTimer: タイマー割り込み処理                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   // 1秒ごとにダッシュボードを更新
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| メイン更新関数: 統計計算 → ダッシュボード描画 → アラートチェック       |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   // NYタイム17:00を基準とした「本日」の開始時刻を取得
   datetime nyDayStart = GetNYDayStart();
   
   // 「本日」が変わったらアラートフラグをリセット
   if(nyDayStart != g_LastNYDayStart)
   {
      ResetAlertFlags();
      g_LastNYDayStart = nyDayStart;
   }
   
   // トレード統計を計算
   TradeStats stats;
   CalculateStats(nyDayStart, stats);
   
   // ダッシュボードを描画
   DrawDashboard(stats);
   
   // 各アラートをチェック・発動
   CheckAllAlerts(stats);
   
   // チャートを再描画
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| NYタイム17:00を基準とした「本日」の開始時刻をサーバー時刻で返す        |
//|                                                                   |
//| 【NYタイム17:00ロールオーバーの仕組み】                               |
//|   FXマーケットでは、ニューヨーク時間の午後5時(17:00)が                |
//|   1日の区切り(ロールオーバー)となっています。                          |
//|   例) NYタイム 2024/01/15 17:00 = サーバー(UTC+2) 2024/01/15 00:00 |
//|                                                                   |
//| 【DST(夏時間)対応の仕組み】                                          |
//|   ニューヨークのDST規則:                                             |
//|   - 開始: 3月第2日曜日(UTC-5 → UTC-4 に切り替え)                   |
//|   - 終了: 11月第1日曜日(UTC-4 → UTC-5 に戻す)                      |
//|   IsDSTActive()関数でUTC時刻が夏時間期間内かを判定します               |
//+------------------------------------------------------------------+
datetime GetNYDayStart()
{
   // 現在のサーバー時刻を取得
   datetime serverNow = TimeCurrent();
   
   // サーバーからNYへのオフセット時間を取得(時間単位)
   int offsetHours = GetServerToNYOffset(serverNow);
   
   // 現在のNYタイムを計算
   // サーバー時刻からオフセット分を引くことでNY時刻に変換
   datetime nyNow = serverNow - offsetHours * 3600;
   
   // NY時刻で本日の17:00(5PM)を計算
   // MqlDateTime構造体を使って日付部分を取り出す
   MqlDateTime nyDt;
   TimeToStruct(nyNow, nyDt);
   
   // NY時刻が17:00より前なら、前日の17:00がロールオーバー時刻
   // NY時刻が17:00以降なら、当日の17:00がロールオーバー時刻
   int nyRolloverHour = 17;
   
   if(nyDt.hour < nyRolloverHour)
   {
      // 前日17:00をNY時刻で構築
      nyDt.hour   = nyRolloverHour;
      nyDt.min    = 0;
      nyDt.sec    = 0;
      datetime nyYest1700 = StructToTime(nyDt);
      // 1日分(86400秒)を引いて前日に
      nyYest1700 -= 86400;
      // NYからサーバー時刻に戻す(オフセット分を足す)
      return nyYest1700 + offsetHours * 3600;
   }
   else
   {
      // 当日17:00をNY時刻で構築
      nyDt.hour   = nyRolloverHour;
      nyDt.min    = 0;
      nyDt.sec    = 0;
      datetime nyToday1700 = StructToTime(nyDt);
      // NYからサーバー時刻に戻す
      return nyToday1700 + offsetHours * 3600;
   }
}

//+------------------------------------------------------------------+
//| サーバー時刻→NYタイムのオフセット(時間)を返す                         |
//| ServerToNYOffsetHours=999 の場合はDSTを考慮して自動計算              |
//|                                                                   |
//| 戻り値の意味: NY時刻 = サーバー時刻 - offsetHours                    |
//|   例) サーバー=UTC+2、NY夏時間=UTC-4 → offsetHours = 6             |
//+------------------------------------------------------------------+
int GetServerToNYOffset(datetime serverTime)
{
   // 手動設定が有効な場合はそちらを優先
   if(ServerToNYOffsetHours != 999)
      return ServerToNYOffsetHours;
   
   // 自動計算: まずサーバーのUTCオフセットを推定
   // MetaTrader5 ではTimeGMT()でUTC時刻を取得できる
   datetime utcNow  = TimeGMT();
   int serverUtcOffset = (int)MathRound((double)(serverTime - utcNow) / 3600.0);
   
   // NYのUTCオフセットをDSTに基づいて決定
   // IsDSTActive()はUTC時刻を受け取る
   int nyUtcOffset = IsDSTActive(utcNow) ? -4 : -5;
   
   // サーバーからNYへのオフセット = サーバーUTCオフセット - NYUTCオフセット
   return serverUtcOffset - nyUtcOffset;
}

//+------------------------------------------------------------------+
//| ニューヨーク夏時間(DST)が有効かどうかを判定する                        |
//|                                                                   |
//| 【米国DST規則】                                                     |
//|   開始: 3月の第2日曜日 02:00 (現地時間) = 07:00 UTC               |
//|   終了: 11月の第1日曜日 02:00 (現地時間) = 07:00 UTC(EST)          |
//|                                                                   |
//| 判定アルゴリズム:                                                    |
//|   1) 月が3月より前 or 11月より後 → 冬時間(DST無効)                  |
//|   2) 月が4月~10月 → 夏時間(DST有効)                               |
//|   3) 3月の場合: 第2日曜日の07:00 UTC以降かどうか                    |
//|   4) 11月の場合: 第1日曜日の07:00 UTC以前かどうか                   |
//+------------------------------------------------------------------+
bool IsDSTActive(datetime utcTime)
{
   MqlDateTime dt;
   TimeToStruct(utcTime, dt);
   
   int month = dt.mon;
   int day   = dt.day;
   int hour  = dt.hour;
   int dow   = dt.day_of_week; // 0=日曜日, 1=月曜日...
   
   // 1月・2月 → 確実に冬時間
   if(month < 3) return false;
   
   // 4月~10月 → 確実に夏時間
   if(month > 3 && month < 11) return true;
   
   // 3月: 第2日曜日の07:00 UTC以降かどうかを判定
   if(month == 3)
   {
      // 3月の第2日曜日を計算
      // まず3月1日の曜日を求める
      int firstDOW = GetFirstDayOfWeek(dt.year, 3); // 3月1日の曜日
      
      // 最初の日曜日 = 1日 + (7 - firstDOW) % 7
      int firstSun = 1 + (7 - firstDOW) % 7;
      // 第2日曜日 = 最初の日曜日 + 7
      int secondSun = firstSun + 7;
      
      // 比較: 現在日時が第2日曜日の07:00 UTC以降かどうか
      if(day > secondSun) return true;
      if(day == secondSun && hour >= 7) return true;
      return false;
   }
   
   // 11月: 第1日曜日の07:00 UTC(EST = UTC-5)以前かどうかを判定
   // 終了時刻: 現地時間 02:00 EST = UTC 07:00
   if(month == 11)
   {
      int firstDOW = GetFirstDayOfWeek(dt.year, 11); // 11月1日の曜日
      int firstSun = 1 + (7 - firstDOW) % 7;
      
      // 第1日曜日の07:00 UTC以前なら夏時間
      if(day < firstSun) return true;
      if(day == firstSun && hour < 7) return true;
      return false;
   }
   
   // 12月 → 冬時間
   return false;
}

//+------------------------------------------------------------------+
//| 指定年月の1日の曜日を返す(0=日曜日)                                  |
//| Tomohiko Sakamoto アルゴリズムを使用                                 |
//+------------------------------------------------------------------+
int GetFirstDayOfWeek(int year, int month)
{
   // Zeller's congruence を簡略化したアルゴリズム
   // month=1,2 の場合は前年の13,14月として計算
   int y = year;
   int m = month;
   if(m < 3)
   {
      m += 12;
      y--;
   }
   int k = y % 100;
   int j = y / 100;
   // Zeller's congruence: 結果 0=土曜日
   int h = (1 + (13*(m+1)/5) + k + (k/4) + (j/4) - 2*j) % 7;
   // 変換: h(0=土) → dow(0=日)
   // h: 0=Sat,1=Sun,2=Mon,3=Tue,4=Wed,5=Thu,6=Fri
   // dow: 0=Sun,1=Mon,2=Tue,3=Wed,4=Thu,5=Fri,6=Sat
   int dow = ((h + 5) % 7) + 1;
   if(dow == 7) dow = 0;
   return dow;
}

//+------------------------------------------------------------------+
//| トレード統計を計算する                                               |
//| nyDayStart: NYロールオーバー以降の取引履歴のみを対象にする              |
//+------------------------------------------------------------------+
void CalculateStats(datetime nyDayStart, TradeStats &stats)
{
   // 統計を初期化
   ZeroMemory(stats);
   
   // 確定損益・統計の計算(クローズ済みポジションから)
   // HistorySelect で本日分の履歴を取得する
   // ★ 重要: 確定した(クローズ済み)取引のみを対象とし、現在進行中の
   //          ポジションは含めない(リペイントしない設計)
   if(HistorySelect(nyDayStart, TimeCurrent()))
   {
      int dealTotal = HistoryDealsTotal();
      
      double totalProfitWins  = 0.0;
      double totalProfitLoss  = 0.0;
      long   totalHoldSec     = 0;
      long   totalWinHoldSec  = 0;
      long   totalLossHoldSec = 0;
      int    currentConsecWins   = 0;
      int    currentConsecLosses = 0;
      
      // 各ディールを走査してトレードごとの損益を集計
      for(int i = 0; i < dealTotal; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         // エントリー方向の確認(OUT=クローズ or IN_OUT=反転のみ対象)
         ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT)
            continue;
         
         // シンボルフィルター(現在のチャートシンボルのみ、または全通貨ペア)
         // 全通貨ペアを対象にする場合は以下のフィルターを外す
         // string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         // if(dealSymbol != Symbol()) continue;
         
         double profit  = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                        + HistoryDealGetDouble(ticket, DEAL_SWAP)
                        + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         // 対応するオープン時刻を取得(ポジションIDから)
         ulong posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         datetime openTime  = 0;
         
         // 同じポジションIDを持つINエントリーを検索してオープン時刻を取得
         for(int j = 0; j < dealTotal; j++)
         {
            ulong tk2 = HistoryDealGetTicket(j);
            if(tk2 == 0) continue;
            if((ulong)HistoryDealGetInteger(tk2, DEAL_POSITION_ID) == posId)
            {
               ENUM_DEAL_ENTRY et2 = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk2, DEAL_ENTRY);
               if(et2 == DEAL_ENTRY_IN || et2 == DEAL_ENTRY_INOUT)
               {
                  openTime = (datetime)HistoryDealGetInteger(tk2, DEAL_TIME);
                  break;
               }
            }
         }
         
         // 保有時間(秒)
         long holdSec = (openTime > 0) ? (long)(closeTime - openTime) : 0;
         
         stats.realizedPnL += profit;
         stats.totalTrades++;
         totalHoldSec += holdSec;
         
         if(profit > 0.0)
         {
            // 勝ちトレード
            stats.wins++;
            totalProfitWins += profit;
            totalWinHoldSec += holdSec;
            if(profit > stats.maxProfit) stats.maxProfit = profit;
            currentConsecWins++;
            currentConsecLosses = 0;
            if(currentConsecWins > stats.consecWins)
               stats.consecWins = currentConsecWins;
         }
         else if(profit < 0.0)
         {
            // 負けトレード
            stats.losses++;
            totalProfitLoss += profit;
            totalLossHoldSec += holdSec;
            if(profit < stats.maxLoss) stats.maxLoss = profit;
            currentConsecLosses++;
            currentConsecWins = 0;
            if(currentConsecLosses > stats.consecLosses)
               stats.consecLosses = currentConsecLosses;
         }
         else
         {
            // ドロー
            stats.draws++;
            currentConsecWins   = 0;
            currentConsecLosses = 0;
         }
      }
      
      // 各平均値を計算
      if(stats.totalTrades > 0)
      {
         stats.avgPnL      = stats.realizedPnL / stats.totalTrades;
         stats.avgHoldSec  = (double)totalHoldSec / stats.totalTrades;
      }
      if(stats.wins > 0)
      {
         stats.avgProfit      = totalProfitWins / stats.wins;
         stats.avgWinHoldSec  = (double)totalWinHoldSec / stats.wins;
      }
      if(stats.losses > 0)
      {
         stats.avgLoss        = totalProfitLoss / stats.losses;
         stats.avgLossHoldSec = (double)totalLossHoldSec / stats.losses;
      }
      
      // 勝率計算 (ドローを除外)
      int decidedTrades = stats.wins + stats.losses;
      if(decidedTrades > 0)
         stats.winRate = (double)stats.wins / decidedTrades * 100.0;
      
      // リスクリワード比率計算
      // リスクリワード = 平均利益 / |平均損失|
      if(stats.losses > 0 && stats.avgLoss != 0.0)
         stats.riskReward = stats.avgProfit / MathAbs(stats.avgLoss);
   }
   
   // 未確定損益(フロートPnL): 現在オープン中の全ポジションから計算
   stats.openPositions = PositionsTotal();
   stats.unrealizedPnL = 0.0;
   for(int i = 0; i < stats.openPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      stats.unrealizedPnL += PositionGetDouble(POSITION_PROFIT)
                           + PositionGetDouble(POSITION_SWAP);
   }
   
   // 合計損益
   stats.totalPnL = stats.realizedPnL + stats.unrealizedPnL;
   
   // 本日の高値・安値レンジを計算
   // 現在のチャートシンボルのD1バーから取得
   CalculateVolatility(nyDayStart, stats);
}

//+------------------------------------------------------------------+
//| 本日のボラティリティ(高値-安値レンジ)を計算する                        |
//+------------------------------------------------------------------+
void CalculateVolatility(datetime nyDayStart, TradeStats &stats)
{
   // M1足を使って本日(NYロールオーバー以降)の高値・安値を取得
   int barCount = iBars(Symbol(), PERIOD_M1);
   
   stats.todayHigh = 0.0;
   stats.todayLow  = DBL_MAX;
   
   // M1バーを逆順(新しい方から)に走査して本日分を集計
   for(int i = 0; i < MathMin(barCount, 1440); i++) // 最大24時間分
   {
      datetime barTime = iTime(Symbol(), PERIOD_M1, i);
      if(barTime < nyDayStart) break; // NY開始より前のバーは無視
      
      double hi = iHigh(Symbol(), PERIOD_M1, i);
      double lo = iLow(Symbol(), PERIOD_M1, i);
      
      if(hi > stats.todayHigh) stats.todayHigh = hi;
      if(lo < stats.todayLow)  stats.todayLow  = lo;
   }
   
   // 高値・安値が有効な場合のみレンジを計算
   if(stats.todayHigh > 0.0 && stats.todayLow < DBL_MAX && stats.todayHigh > stats.todayLow)
   {
      stats.volRange     = stats.todayHigh - stats.todayLow;
      // レート比(%) = レンジ / 安値 * 100
      if(stats.todayLow > 0.0)
         stats.volRangeRate = stats.volRange / stats.todayLow * 100.0;
   }
   else
   {
      stats.todayHigh    = 0.0;
      stats.todayLow     = 0.0;
      stats.volRange     = 0.0;
      stats.volRangeRate = 0.0;
   }
}

//+------------------------------------------------------------------+
//| 秒数を "Xh Ym" or "Ym Zs" の文字列に変換するヘルパー関数             |
//+------------------------------------------------------------------+
string FormatHoldTime(double seconds)
{
   if(seconds <= 0.0) return "0m 0s";
   
   long s = (long)seconds;
   long h = s / 3600;
   long m = (s % 3600) / 60;
   long sec = s % 60;
   
   if(h > 0)
      return StringFormat("%dh %dm", (int)h, (int)m);
   else
      return StringFormat("%dm %ds", (int)m, (int)sec);
}

//+------------------------------------------------------------------+
//| 数値の絶対値が閾値の何%かによって色を返す(信号灯ロジック)              |
//| ratio: 現在値/閾値 の比率(0.0~1.0以上)                             |
//| 80%未満=緑、80%以上=黄、100%以上=赤                                |
//+------------------------------------------------------------------+
color GetTrafficLightColor(double currentVal, double threshold, bool lowerIsBad = true)
{
   if(threshold == 0.0) return CLR_VALUE;
   
   double ratio;
   if(lowerIsBad)
      // 損失など: 現在の絶対値が閾値絶対値に近いほど危険
      ratio = MathAbs(currentVal) / MathAbs(threshold);
   else
      // 回数など: 現在値が閾値に近いほど危険
      ratio = (threshold != 0.0) ? currentVal / threshold : 0.0;
   
   if(ratio >= 1.0) return CLR_RED;
   if(ratio >= 0.8) return CLR_YELLOW;
   return CLR_GREEN;
}

//+------------------------------------------------------------------+
//| ダッシュボードの全チャートオブジェクトを削除する                        |
//+------------------------------------------------------------------+
void DeleteAllPanelObjects()
{
   // プレフィックスで始まるオブジェクトを全削除
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PANEL_PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| ラベルオブジェクトを作成または更新するヘルパー関数                      |
//+------------------------------------------------------------------+
void SetLabel(string name, string text, int x, int y,
              color clr = CLR_VALUE, int fontSize = PANEL_FONT_SIZE,
              string fontName = PANEL_FONT, uint anchor = ANCHOR_LEFT_UPPER)
{
   string fullName = PANEL_PREFIX + name;
   
   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER,    DashboardCorner);
      ObjectSetInteger(0, fullName, OBJPROP_ANCHOR,    anchor);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, fullName, OBJPROP_HIDDEN,    true);
      ObjectSetInteger(0, fullName, OBJPROP_BACK,      false);
   }
   
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetString( 0, fullName, OBJPROP_TEXT,      text);
   ObjectSetString( 0, fullName, OBJPROP_FONT,      fontName);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR,     clr);
}

//+------------------------------------------------------------------+
//| 背景矩形を作成または更新するヘルパー関数                               |
//+------------------------------------------------------------------+
void SetRect(string name, int x, int y, int width, int height,
             color bgColor, color borderColor = CLR_BORDER)
{
   string fullName = PANEL_PREFIX + name;
   
   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER,    DashboardCorner);
      ObjectSetInteger(0, fullName, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, fullName, OBJPROP_HIDDEN,    true);
      ObjectSetInteger(0, fullName, OBJPROP_BACK,      true);
   }
   
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, fullName, OBJPROP_XSIZE,      width);
   ObjectSetInteger(0, fullName, OBJPROP_YSIZE,      height);
   ObjectSetInteger(0, fullName, OBJPROP_BGCOLOR,    bgColor);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR,      borderColor);
   ObjectSetInteger(0, fullName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, fullName, OBJPROP_WIDTH,       1);
}

//+------------------------------------------------------------------+
//| ダッシュボード全体を描画する                                          |
//+------------------------------------------------------------------+
void DrawDashboard(const TradeStats &stats)
{
   int ox = DashboardOffsetX; // X起点
   int oy = DashboardOffsetY; // Y起点
   int lh = 18;               // 行の高さ(ピクセル)
   int pw = PANEL_WIDTH;      // パネル幅
   int px = ox + 4;           // テキスト左マージン
   int vx = ox + pw - 8;     // 値テキスト右端X
   
   // パネルの総高さを計算(行数から概算)
   int panelH = lh * 26 + 20;
   
   //--- メインパネル背景 ---
   SetRect("BG", ox - 2, oy - 2, pw + 4, panelH + 4, CLR_BG, CLR_BORDER);
   
   //--- ヘッダー ---
   SetRect("HDR", ox - 2, oy - 2, pw + 4, lh + 8, CLR_HEADER, CLR_BORDER);
   
   // タイトル
   SetLabel("TITLE", "📊 トレードモニター  [" + Symbol() + "]",
            px, oy, CLR_TITLE, PANEL_FONT_SIZE + 1);
   
   // NYロールオーバー時刻表示
   datetime nyStart = GetNYDayStart();
   string rollStr   = "NY開始: " + TimeToString(nyStart, TIME_DATE|TIME_MINUTES);
   SetLabel("ROLL", rollStr, ox + pw - 180, oy, CLR_LABEL, PANEL_FONT_SIZE - 1);
   
   int row = 1;
   
   //--- 区切り線1 ---
   SetRect("DIV1", ox - 2, oy + lh * row + 4, pw + 4, 1, CLR_DIVIDER, CLR_DIVIDER);
   row++;
   
   //--- 損益セクション ---
   SetLabel("SEC_PNL", "■ 損益サマリー", px, oy + lh * row, CLR_TITLE, PANEL_FONT_SIZE);
   row++;
   
   // 本日の損益(確定+未確定)
   color totalPnlClr = stats.totalPnL >= 0 ? CLR_PROFIT : CLR_LOSS;
   SetLabel("LBL_TOTAL",  "本日の損益",      px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_TOTAL",  StringFormat("%.2f", stats.totalPnL),
            vx, oy + lh * row, totalPnlClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 確定損益
   color realClr = stats.realizedPnL >= 0 ? CLR_PROFIT : CLR_LOSS;
   color realTLClr = CLR_VALUE;
   if(Alert1_Enable && Alert1_Threshold != 0.0)
      realTLClr = GetTrafficLightColor(stats.realizedPnL, Alert1_Threshold, true);
   if(Alert2_Enable && Alert2_Threshold != 0.0 && stats.realizedPnL >= 0)
      realTLClr = GetTrafficLightColor(stats.realizedPnL, Alert2_Threshold, false);
   SetLabel("LBL_REAL",  "  確定損益",       px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_REAL",  StringFormat("%.2f", stats.realizedPnL),
            vx, oy + lh * row, realClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 未確定損益
   color floatClr = stats.unrealizedPnL >= 0 ? CLR_PROFIT : CLR_LOSS;
   SetLabel("LBL_FLOAT", "  未確定損益(フロート)", px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_FLOAT", StringFormat("%.2f", stats.unrealizedPnL),
            vx, oy + lh * row, floatClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   //--- 区切り線2 ---
   SetRect("DIV2", ox - 2, oy + lh * row + 4, pw + 4, 1, CLR_DIVIDER, CLR_DIVIDER);
   row++;
   
   //--- トレード統計セクション ---
   SetLabel("SEC_STAT", "■ トレード統計", px, oy + lh * row, CLR_TITLE, PANEL_FONT_SIZE);
   row++;
   
   // トレード回数
   color tradeClr = CLR_VALUE;
   if(Alert3_Enable && Alert3_Threshold > 0)
      tradeClr = GetTrafficLightColor(stats.totalTrades, Alert3_Threshold, false);
   SetLabel("LBL_TRADES", "回数/勝/負/ドロー", px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_TRADES",
            StringFormat("%d / %d / %d / %d",
                         stats.totalTrades, stats.wins, stats.losses, stats.draws),
            vx, oy + lh * row, tradeClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 勝率
   SetLabel("LBL_WR",  "勝率",      px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_WR",  stats.totalTrades > 0
                        ? StringFormat("%.1f%%", stats.winRate)
                        : "---",
            vx, oy + lh * row, CLR_VALUE, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // リスクリワード比率
   SetLabel("LBL_RR",  "リスクリワード",  px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_RR",  (stats.wins > 0 && stats.losses > 0)
                        ? StringFormat("%.2f", stats.riskReward)
                        : "---",
            vx, oy + lh * row, CLR_VALUE, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 平均損益
   SetLabel("LBL_AVG",  "平均損益",  px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_AVG",  stats.totalTrades > 0
                         ? StringFormat("%.2f", stats.avgPnL)
                         : "---",
            vx, oy + lh * row,
            (stats.avgPnL >= 0 ? CLR_PROFIT : CLR_LOSS),
            PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   //--- 区切り線3 ---
   SetRect("DIV3", ox - 2, oy + lh * row + 4, pw + 4, 1, CLR_DIVIDER, CLR_DIVIDER);
   row++;
   
   //--- 利益・損失詳細 ---
   SetLabel("SEC_DETAIL", "■ 利益/損失詳細", px, oy + lh * row, CLR_TITLE, PANEL_FONT_SIZE);
   row++;
   
   // 平均利益 / 最大利益
   SetLabel("LBL_PROFIT",  "平均利益 / 最大利益", px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_PROFIT",
            stats.wins > 0
            ? StringFormat("%.2f / %.2f", stats.avgProfit, stats.maxProfit)
            : "--- / ---",
            vx, oy + lh * row, CLR_PROFIT, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 平均損失 / 最大損失
   SetLabel("LBL_LOSS",   "平均損失 / 最大損失", px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_LOSS",
            stats.losses > 0
            ? StringFormat("%.2f / %.2f", stats.avgLoss, stats.maxLoss)
            : "--- / ---",
            vx, oy + lh * row, CLR_LOSS, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 連勝数
   color consWinClr = CLR_VALUE;
   if(Alert4_Enable && Alert4_Threshold > 0)
      consWinClr = GetTrafficLightColor(stats.consecWins, Alert4_Threshold, false);
   SetLabel("LBL_CWIN",  "連勝数",   px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_CWIN",  IntegerToString(stats.consecWins) + " 連勝",
            vx, oy + lh * row, consWinClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 連敗数
   color consLossClr = CLR_VALUE;
   if(Alert5_Enable && Alert5_Threshold > 0)
      consLossClr = GetTrafficLightColor(stats.consecLosses, Alert5_Threshold, false);
   SetLabel("LBL_CLOSS", "連敗数",   px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_CLOSS", IntegerToString(stats.consecLosses) + " 連敗",
            vx, oy + lh * row, consLossClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   //--- 区切り線4 ---
   SetRect("DIV4", ox - 2, oy + lh * row + 4, pw + 4, 1, CLR_DIVIDER, CLR_DIVIDER);
   row++;
   
   //--- 保有時間セクション ---
   SetLabel("SEC_HOLD", "■ 保有時間", px, oy + lh * row, CLR_TITLE, PANEL_FONT_SIZE);
   row++;
   
   // 平均保有時間
   SetLabel("LBL_HOLD",      "平均保有時間",       px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_HOLD",
            stats.totalTrades > 0 ? FormatHoldTime(stats.avgHoldSec) : "---",
            vx, oy + lh * row, CLR_VALUE, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 勝ちトレード平均保有時間
   SetLabel("LBL_WHOLD",     "  勝ちトレード平均",  px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_WHOLD",
            stats.wins > 0 ? FormatHoldTime(stats.avgWinHoldSec) : "---",
            vx, oy + lh * row, CLR_PROFIT, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // 負けトレード平均保有時間
   SetLabel("LBL_LHOLD",     "  負けトレード平均",  px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_LHOLD",
            stats.losses > 0 ? FormatHoldTime(stats.avgLossHoldSec) : "---",
            vx, oy + lh * row, CLR_LOSS, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   //--- 区切り線5 ---
   SetRect("DIV5", ox - 2, oy + lh * row + 4, pw + 4, 1, CLR_DIVIDER, CLR_DIVIDER);
   row++;
   
   //--- ポジション / ボラティリティセクション ---
   SetLabel("SEC_POS", "■ 現況", px, oy + lh * row, CLR_TITLE, PANEL_FONT_SIZE);
   row++;
   
   // 同時保有ポジション数
   color posClr = CLR_VALUE;
   if(Alert6_Enable && Alert6_Threshold > 0)
      posClr = GetTrafficLightColor(stats.openPositions, Alert6_Threshold, false);
   SetLabel("LBL_POS",  "保有ポジション数",  px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_POS",  IntegerToString(stats.openPositions) + " 件",
            vx, oy + lh * row, posClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   // ボラティリティ(今日のレンジ)
   string volStr = "---";
   if(stats.volRange > 0.0)
   {
      int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
      volStr = StringFormat("%.*f  (%.3f%%)",
                            digits, stats.volRange, stats.volRangeRate);
   }
   color volClr = CLR_VALUE;
   // ボラアラートの閾値との比較で色付け
   if(Alert7_Enable && Alert7_Threshold > 0.0 && stats.volRange > 0.0)
   {
      double compareVal = (Alert7_Mode == "Rate(%)") ? stats.volRangeRate : stats.volRange;
      if(Alert7_Direction == "Upper")
         volClr = (compareVal >= Alert7_Threshold * 0.8) ? CLR_YELLOW : CLR_GREEN;
      else
         volClr = (compareVal <= Alert7_Threshold * 1.2) ? CLR_YELLOW : CLR_GREEN;
      if(Alert7_Direction == "Upper" && compareVal >= Alert7_Threshold) volClr = CLR_RED;
      if(Alert7_Direction == "Lower" && compareVal <= Alert7_Threshold) volClr = CLR_RED;
   }
   SetLabel("LBL_VOL",  "本日レンジ(H-L)",   px, oy + lh * row, CLR_LABEL);
   SetLabel("VAL_VOL",  volStr,
            vx, oy + lh * row, volClr, PANEL_FONT_SIZE, PANEL_FONT, ANCHOR_RIGHT_UPPER);
   row++;
   
   //--- フッター: 最終更新時刻 ---
   SetRect("FOOTER", ox - 2, oy + lh * row + 4, pw + 4, lh, CLR_HEADER, CLR_BORDER);
   SetLabel("FOOT_TIME",
            "更新: " + TimeToString(TimeCurrent(), TIME_SECONDS),
            px, oy + lh * row + 4, CLR_LABEL, PANEL_FONT_SIZE - 1);
}

//+------------------------------------------------------------------+
//| 全アラートをチェックし、条件を満たしたらアラートを発動する               |
//+------------------------------------------------------------------+
void CheckAllAlerts(const TradeStats &stats)
{
   // アラート1: 損失限度額
   CheckLossAlert(stats);
   // アラート2: 目標利益額
   CheckProfitAlert(stats);
   // アラート3: トレード回数
   CheckTradeCountAlert(stats);
   // アラート4: 連勝数
   CheckConsecWinsAlert(stats);
   // アラート5: 連敗数
   CheckConsecLossesAlert(stats);
   // アラート6: 同時保有ポジション数
   CheckOpenPositionsAlert(stats);
   // アラート7: ボラティリティ
   CheckVolatilityAlert(stats);
}

//+------------------------------------------------------------------+
//| アラート1: 損失限度額チェック                                         |
//| 本日の確定損益(実現損益のみ)が設定した損失限度に達したら発動             |
//| ※ 未確定(フロート)損益は含めない                                      |
//+------------------------------------------------------------------+
void CheckLossAlert(const TradeStats &stats)
{
   if(!Alert1_Enable || g_Alert1Fired) return;
   
   // 損失限度の閾値はマイナス値で設定されている想定
   // 確定損益が閾値以下(より大きな損失)になったらアラート
   double threshold = MathMin(Alert1_Threshold, 0.0); // 安全のためマイナス確認
   if(threshold >= 0.0) threshold = -MathAbs(Alert1_Threshold);
   
   if(stats.realizedPnL <= threshold)
   {
      FireAlert(Alert1_Message, Alert1_BoxColor, Alert1_TxtColor);
      g_Alert1Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート2: 目標利益額チェック                                         |
//| 本日の確定損益(実現損益のみ)が設定した目標に達したら発動                 |
//| ※ 未確定(フロート)損益は含めない                                      |
//+------------------------------------------------------------------+
void CheckProfitAlert(const TradeStats &stats)
{
   if(!Alert2_Enable || g_Alert2Fired) return;
   
   double threshold = MathAbs(Alert2_Threshold); // プラス確認
   if(stats.realizedPnL >= threshold)
   {
      FireAlert(Alert2_Message, Alert2_BoxColor, Alert2_TxtColor);
      g_Alert2Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート3: トレード回数チェック                                        |
//+------------------------------------------------------------------+
void CheckTradeCountAlert(const TradeStats &stats)
{
   if(!Alert3_Enable || g_Alert3Fired) return;
   
   if(stats.totalTrades >= Alert3_Threshold)
   {
      FireAlert(Alert3_Message, Alert3_BoxColor, Alert3_TxtColor);
      g_Alert3Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート4: 連勝数チェック                                             |
//+------------------------------------------------------------------+
void CheckConsecWinsAlert(const TradeStats &stats)
{
   if(!Alert4_Enable || g_Alert4Fired) return;
   
   if(stats.consecWins >= Alert4_Threshold)
   {
      FireAlert(Alert4_Message, Alert4_BoxColor, Alert4_TxtColor);
      g_Alert4Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート5: 連敗数チェック                                             |
//+------------------------------------------------------------------+
void CheckConsecLossesAlert(const TradeStats &stats)
{
   if(!Alert5_Enable || g_Alert5Fired) return;
   
   if(stats.consecLosses >= Alert5_Threshold)
   {
      FireAlert(Alert5_Message, Alert5_BoxColor, Alert5_TxtColor);
      g_Alert5Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート6: 同時保有ポジション数チェック                                 |
//+------------------------------------------------------------------+
void CheckOpenPositionsAlert(const TradeStats &stats)
{
   if(!Alert6_Enable || g_Alert6Fired) return;
   
   if(stats.openPositions > Alert6_Threshold)
   {
      FireAlert(Alert6_Message, Alert6_BoxColor, Alert6_TxtColor);
      g_Alert6Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラート7: ボラティリティチェック                                       |
//| Mode: "Rate(%)" → レンジのレート比率で判定                           |
//|        "Price"   → レンジの価格差で判定                              |
//| Direction: "Upper" → 閾値以上になったらアラート(高ボラ警告)            |
//|             "Lower" → 閾値以下になったらアラート(低ボラ警告)           |
//+------------------------------------------------------------------+
void CheckVolatilityAlert(const TradeStats &stats)
{
   if(!Alert7_Enable || g_Alert7Fired) return;
   if(stats.volRange <= 0.0) return;
   
   // 比較する値を選択
   double compareVal = (Alert7_Mode == "Rate(%)") ? stats.volRangeRate : stats.volRange;
   
   bool triggered = false;
   if(Alert7_Direction == "Upper" && compareVal >= Alert7_Threshold)
      triggered = true;
   else if(Alert7_Direction == "Lower" && compareVal <= Alert7_Threshold)
      triggered = true;
   
   if(triggered)
   {
      FireAlert(Alert7_Message, Alert7_BoxColor, Alert7_TxtColor);
      g_Alert7Fired = true;
   }
}

//+------------------------------------------------------------------+
//| アラートを実際に発動する(ポップアップ + チャートオブジェクト通知)         |
//+------------------------------------------------------------------+
void FireAlert(string message, color boxColor, color textColor)
{
   // MT5標準のポップアップアラートを表示
   Alert(message);
   
   // チャート上にアラートバナーを表示
   string bannerName = PANEL_PREFIX + "ALERT_BANNER";
   string timeName   = PANEL_PREFIX + "ALERT_TIME";
   
   int bx = DashboardOffsetX;
   int by = DashboardOffsetY + 500; // ダッシュボードの下に表示
   
   // バナー背景矩形
   if(ObjectFind(0, bannerName) < 0)
      ObjectCreate(0, bannerName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bannerName, OBJPROP_CORNER,    DashboardCorner);
   ObjectSetInteger(0, bannerName, OBJPROP_XDISTANCE, bx - 2);
   ObjectSetInteger(0, bannerName, OBJPROP_YDISTANCE, by);
   ObjectSetInteger(0, bannerName, OBJPROP_XSIZE,     PANEL_WIDTH + 4);
   ObjectSetInteger(0, bannerName, OBJPROP_YSIZE,     40);
   ObjectSetInteger(0, bannerName, OBJPROP_BGCOLOR,   boxColor);
   ObjectSetInteger(0, bannerName, OBJPROP_COLOR,     boxColor);
   ObjectSetInteger(0, bannerName, OBJPROP_BACK,      false);
   ObjectSetInteger(0, bannerName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bannerName, OBJPROP_HIDDEN,    true);
   
   // バナーテキスト
   if(ObjectFind(0, timeName) < 0)
      ObjectCreate(0, timeName, OBJ_LABEL, 0, 0, 0);
   // メッセージが長い場合は切り詰める
   string dispMsg = StringLen(message) > 40 ? StringSubstr(message, 0, 38) + "…" : message;
   ObjectSetString( 0, timeName, OBJPROP_TEXT,      "⚠ " + dispMsg);
   ObjectSetInteger(0, timeName, OBJPROP_CORNER,    DashboardCorner);
   ObjectSetInteger(0, timeName, OBJPROP_XDISTANCE, bx + 4);
   ObjectSetInteger(0, timeName, OBJPROP_YDISTANCE, by + 6);
   ObjectSetString( 0, timeName, OBJPROP_FONT,      PANEL_FONT);
   ObjectSetInteger(0, timeName, OBJPROP_FONTSIZE,  PANEL_FONT_SIZE);
   ObjectSetInteger(0, timeName, OBJPROP_COLOR,     textColor);
   ObjectSetInteger(0, timeName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, timeName, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, timeName, OBJPROP_BACK,      false);
}

//+------------------------------------------------------------------+
//| アラート発動済みフラグを全てリセットする                                 |
//| (NYロールオーバーで新しい日が始まった時に呼ばれる)                       |
//+------------------------------------------------------------------+
void ResetAlertFlags()
{
   g_Alert1Fired = false;
   g_Alert2Fired = false;
   g_Alert3Fired = false;
   g_Alert4Fired = false;
   g_Alert5Fired = false;
   g_Alert6Fired = false;
   g_Alert7Fired = false;
   
   // アラートバナーを削除
   ObjectDelete(0, PANEL_PREFIX + "ALERT_BANNER");
   ObjectDelete(0, PANEL_PREFIX + "ALERT_TIME");
}

//+------------------------------------------------------------------+
//| END OF FILE                                                       |
//+------------------------------------------------------------------+
