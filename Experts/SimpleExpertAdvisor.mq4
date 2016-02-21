#property copyright "Andrzej Wojtowicz"
#property link      "https://github.com/andre-wojtowicz"
#property version   "1.00"
#property strict

#include <SEAutils.mqh>

// input variables
extern bool   UseMinEquity    = true,
              UseMaxSpread    = true,
              DynamicLotSize  = true,
              UseTrailingStop = true,
              CheckOncePerBar = true,
              TwoStepOrder    = false;
extern double EquityPercent   =    2,
              FixedLotSize    =  0.1,
              StopLoss        =   50, 
              TakeProfit      =  100;
extern int    MinimumEquity   = 8000,
              MaximumSpread   =    5,
              Slippage        =    5,
              MinStopMargin   =    5,
              TrailingStop    =   50,
              MinimumProfit   =   50,
              MagicNumber     = 1337,
              FastMAPeriod    =   10,
              SlowMAPeriod    =   20,
              MaxOrderRetry   =    5;
              
// global variables
int BuyTicket  = 0, 
    SellTicket = 0;
    
// variables to be set in OnInit
int    UseSlippage;
double UsePoint;

datetime CurrentTimeStamp; 


int OnInit()
{
    UsePoint    = GetPipPoint(Symbol());
    UseSlippage = GetSlippage(Symbol(), Slippage);
    
    CurrentTimeStamp = Time[0];
    
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
    // check if buy/sell orders are already closed by s/l or t/p...
    
    if (BuyTicket > 0)
    {
        if (OrderSelect(BuyTicket, SELECT_BY_TICKET))
        {
            if (OrderCloseTime() > 0)
                BuyTicket = 0;
        }
        else
            HandleLastError();
    }
    
    if (SellTicket > 0)
    {
        if (OrderSelect(SellTicket, SELECT_BY_TICKET))
        {
            if (OrderCloseTime() > 0)
                SellTicket = 0;
        }
        else
            HandleLastError();
    }
    
    // ...update trailing stops...
    
    if (UseTrailingStop)
    {
        if (BuyTicket > 0)
        {
            if (BuyTrailingStop(Symbol(), BuyTicket, TrailingStop, MinimumProfit, MaxOrderRetry))
                Print("Trailing stop updated in buy order");
        }
        
        if (SellTicket > 0)
        {
            if (SellTrailingStop(Symbol(), SellTicket, TrailingStop, MinimumProfit, MaxOrderRetry))
                Print("Trailing stop updated in sell order");
        }
    }
    
    // ...and proceed
    
    // check whether trader only on new bars    
    int BarShift = 0;
    
    if (CheckOncePerBar)
    {
        if (CurrentTimeStamp != Time[0])
        {
            BarShift = 1;
            CurrentTimeStamp = Time[0];
        }
        else
            return; // wait for new bar
    }
    
    // check account equity
    if (UseMinEquity && AccountEquity() < MinimumEquity)
    {
        Alert("Equity too low (", AccountEquity(), "), no new orders.");
        return;
    }
    
    // check spread
    if (UseMaxSpread && MarketInfo(Symbol(), MODE_SPREAD) > MaximumSpread)
    {
        Alert("Spread too large (", MarketInfo(Symbol(), MODE_SPREAD), "), no new orders.");
        return;
    }
    
    // calculate lot size
    double LotSize = CalcLotSize(AccountEquity(), Symbol(), DynamicLotSize, EquityPercent, StopLoss, FixedLotSize);
    VerifyLotSize(LotSize);
    
    // get adjusted SMA indicators
    double FastMA = NormalizeDouble(iMA(NULL, 0, FastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, BarShift), Digits()),
           SlowMA = NormalizeDouble(iMA(NULL, 0, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, BarShift), Digits());
    
    // check for sending buy order
    if (FastMA > SlowMA && BuyTicket == 0)
    {        
        // check for holding short position and close it
        if (SellTicket > 0)
        {
            if (CloseOrder(Symbol(), SellTicket, T_SELL, UseSlippage, MaxOrderRetry))
            {
                Print("Sell order closed.");
                SellTicket = 0;
            }
        }
        
        // take long position
        if (TwoStepOrder)
        {
            BuyTicket = OpenOrder(Symbol(), T_BUY, LotSize, UseSlippage, 0, 0, MagicNumber, MaxOrderRetry, "SEA buy order");
        
            if (BuyTicket > 0)
            {
                Print("Buy order sent.");
                
                // add s/l and t/p
                
                if (!OrderSelect(BuyTicket, SELECT_BY_TICKET))
                    HandleLastError();
                double OpenPrice = OrderOpenPrice();
                
                // calculate s/l and t/p
                double BuyStopLoss   = CalcStopLoss(T_BUY, StopLoss, UsePoint, OpenPrice),
                       BuyTakeProfit = CalcTakeProfit(T_BUY, TakeProfit, UsePoint, OpenPrice);
                       
                AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, BuyStopLoss);
                AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, BuyTakeProfit);
                    
                if (AddStopLossTakeProfit(BuyTicket, OpenPrice, BuyStopLoss, BuyTakeProfit, MaxOrderRetry))
                    Print("Buy order - added s/l and t/p.");
            }
        }
        else
        {
            double OpenPrice = MarketInfo(Symbol(), MODE_ASK);
            
            double BuyStopLoss   = CalcStopLoss(T_BUY, StopLoss, UsePoint, OpenPrice),
                   BuyTakeProfit = CalcTakeProfit(T_BUY, TakeProfit, UsePoint, OpenPrice);
                       
            AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, BuyStopLoss);
            AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, BuyTakeProfit);
            
            BuyTicket = OpenOrder(Symbol(), T_BUY, LotSize, UseSlippage, BuyStopLoss, BuyTakeProfit, MagicNumber, MaxOrderRetry, "SEA buy order");
            
            if (BuyTicket > 0)
                Print("Buy order sent.");
        }
    }
    // check for sending sell order
    else if (FastMA < SlowMA && SellTicket == 0)
    {
        // check for holding long position and close it
        if (BuyTicket > 0)
        {
            if (CloseOrder(Symbol(), BuyTicket, T_BUY, UseSlippage, MaxOrderRetry))
            {
                Print("Buy order closed.");
                BuyTicket = 0;
            }
        }
        
        // take short position
        if (TwoStepOrder)
        {
            SellTicket = OpenOrder(Symbol(), T_SELL, LotSize, UseSlippage, 0, 0, MagicNumber, MaxOrderRetry, "SEA sell order");
    
            if (SellTicket > 0)
            {
                Print("Sell order sent.");
                
                // add s/l and t/p
                
                if (!OrderSelect(SellTicket, SELECT_BY_TICKET))
                    HandleLastError();
                double OpenPrice = OrderOpenPrice();
    
                // calculate s/l and t/p
                double SellStopLoss   = CalcStopLoss(T_SELL, StopLoss, UsePoint, OpenPrice),
                       SellTakeProfit = CalcTakeProfit(T_SELL, TakeProfit, UsePoint, OpenPrice);
                
                AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, SellStopLoss);
                AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, SellTakeProfit);
                
                if (AddStopLossTakeProfit(SellTicket, OpenPrice, SellStopLoss, SellTakeProfit, MaxOrderRetry))
                    Print("Sell order - added s/l and t/p.");
            }
        }
        else
        {
            double OpenPrice = MarketInfo(Symbol(), MODE_BID);
            
            double SellStopLoss   = CalcStopLoss(T_SELL, StopLoss, UsePoint, OpenPrice),
                   SellTakeProfit = CalcTakeProfit(T_SELL, TakeProfit, UsePoint, OpenPrice);
                       
            AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, SellStopLoss);
            AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, SellTakeProfit);
            
            SellTicket = OpenOrder(Symbol(), T_SELL, LotSize, UseSlippage, SellStopLoss, SellTakeProfit, MagicNumber, MaxOrderRetry, "SEA sell order");
            
            if (SellTicket > 0)
                Print("Sell order sent.");
        }
    }
}