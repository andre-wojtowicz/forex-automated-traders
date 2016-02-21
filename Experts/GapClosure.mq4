#property copyright "Andrzej Wojtowicz"
#property link      "https://github.com/andre-wojtowicz"
#property version   "1.00"
#property strict

#include <SEAutils.mqh>

// input variables
extern bool   UseMinEquity     = true,
              UseMaxSpread     = true,
              DynamicLotSize   = true,
              TwoStepOrder     = false;
extern double EquityPercent    =    2,
              FixedLotSize     =  0.1,
              StopLossFactor   =    1, 
              TakeProfitFactor =    1;
extern int    MinimumEquity    = 8000,
              MaximumSpread    =    5,
              MinGap           =   50,
              Slippage         =    5,
              MinStopMargin    =    5,
              MagicNumber      = 1338,
              MaxOrderRetry    =    5;
              
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
    if (CurrentTimeStamp != Time[0])
        CurrentTimeStamp = Time[0];
    else
        return; // wait for new bar
        
    if (MathAbs(TimeDayOfWeek(Time[1]) - TimeDayOfWeek(Time[0])) <= 1)
        return; // wait for weekend break
        
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
     
     
    // proceed...
       
    double CandleClosePrice = iClose(Symbol(), PERIOD_CURRENT, 1),
           CandleOpenPrice  = iOpen(Symbol(), PERIOD_CURRENT, 0);
           
    Print(StringConcatenate("op: ", CandleOpenPrice, " cl:", CandleClosePrice));
           
    int Gap = (int)(MathAbs(CandleClosePrice - CandleOpenPrice) * 10 / UsePoint);
    
    if (Gap < MinGap)
        return;

    // calculate lot size
    double LotSize = CalcLotSize(AccountEquity(), Symbol(), DynamicLotSize, EquityPercent, Gap /*StopLoss*/, FixedLotSize);
    VerifyLotSize(LotSize);

    int Ticket;

    if (CandleClosePrice > CandleOpenPrice)
    {
        // take long position
        
        if (TwoStepOrder)
        {
            Ticket = OpenOrder(Symbol(), T_BUY, LotSize, UseSlippage, 0, 0, MagicNumber, MaxOrderRetry, "SEA buy order");
        
            if (Ticket > 0)
            {
                Print("Buy order sent.");
                
                // add s/l and t/p
                
                if (!OrderSelect(Ticket, SELECT_BY_TICKET))
                    HandleLastError();
                double OpenPrice = OrderOpenPrice();
                
                // calculate s/l and t/p
                double BuyStopLoss   = CandleOpenPrice - (Gap  / 10 * UsePoint) * StopLossFactor,
                       BuyTakeProfit = CandleClosePrice - (Gap  / 10 * UsePoint) * (1 - TakeProfitFactor);
                       
                AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, BuyStopLoss);
                AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, BuyTakeProfit);
                    
                if (AddStopLossTakeProfit(Ticket, OpenPrice, BuyStopLoss, BuyTakeProfit, MaxOrderRetry))
                    Print("Buy order - added s/l and t/p.");
            }
        }
        else
        {
            double OpenPrice = MarketInfo(Symbol(), MODE_ASK);
            
            double BuyStopLoss   = CandleOpenPrice - (Gap / 10 * UsePoint) * StopLossFactor,
                   BuyTakeProfit = CandleClosePrice - (Gap  / 10 * UsePoint) * (1 - TakeProfitFactor);
                       
            AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, BuyStopLoss);
            AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, BuyTakeProfit);
            
            Ticket = OpenOrder(Symbol(), T_BUY, LotSize, UseSlippage, BuyStopLoss, BuyTakeProfit, MagicNumber, MaxOrderRetry, "SEA buy order");
            
            if (Ticket > 0)
                Print("Buy order sent.");
        }
    }
    else
    {
        // take short position
        if (TwoStepOrder)
        {
            Ticket = OpenOrder(Symbol(), T_SELL, LotSize, UseSlippage, 0, 0, MagicNumber, MaxOrderRetry, "SEA sell order");
    
            if (Ticket > 0)
            {
                Print("Sell order sent.");
                
                // add s/l and t/p
                
                if (!OrderSelect(Ticket, SELECT_BY_TICKET))
                    HandleLastError();
                double OpenPrice = OrderOpenPrice();
    
                // calculate s/l and t/p
                double SellStopLoss   = CandleOpenPrice + (Gap  / 10 * UsePoint) * StopLossFactor,
                       SellTakeProfit = CandleClosePrice + (Gap  / 10 * UsePoint) * (1 - TakeProfitFactor);
                
                AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, SellStopLoss);
                AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, SellTakeProfit);
                
                if (AddStopLossTakeProfit(Ticket, OpenPrice, SellStopLoss, SellTakeProfit, MaxOrderRetry))
                    Print("Sell order - added s/l and t/p.");
            }
        }
        else
        {
            double OpenPrice = MarketInfo(Symbol(), MODE_BID);
            
            double SellStopLoss   = CandleOpenPrice + (Gap  / 10 * UsePoint) * StopLossFactor,
                   SellTakeProfit = CandleClosePrice + (Gap  / 10 * UsePoint) * (1 - TakeProfitFactor);
                       
            AdjustToUpperStopLevel(Symbol(), UsePoint, MinStopMargin, SellStopLoss);
            AdjustToLowerStopLevel(Symbol(), UsePoint, MinStopMargin, SellTakeProfit);
            
            Ticket = OpenOrder(Symbol(), T_SELL, LotSize, UseSlippage, SellStopLoss, SellTakeProfit, MagicNumber, MaxOrderRetry, "SEA sell order");
            
            if (Ticket > 0)
                Print("Sell order sent.");
        }
    }
}
