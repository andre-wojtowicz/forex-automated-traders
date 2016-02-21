#property copyright "Andrzej Wojtowicz"
#property link      "https://github.com/andre-wojtowicz"
#property strict

#include <stdlib.mqh>

enum orderType
{
    T_BUY,
    T_SELL
};

// standard markets utils

double GetPipPoint(const string argSymbol)
{
    int CalcDigits = (int)MarketInfo(argSymbol, MODE_DIGITS);
    
    if (CalcDigits == 2 || CalcDigits == 3)
        return 0.01;
    // else if (CalcDigits == 4 || CalcDigits == 5)
    return 0.0001;
}

int GetSlippage(const string argSymbol, 
                const int    argSlippagePips)
{
    int CalcDigits = (int)MarketInfo(argSymbol, MODE_DIGITS);
    
    if (CalcDigits == 2 || CalcDigits == 4)
        return argSlippagePips;
    // else if (CalcDigits == 3 || CalcDigits == 5)
    return argSlippagePips * 10;
}

// main functions

double CalcLotSize(const double argAccountEquity,
                   const string argSymbol,
                   const bool   argDynamicLotSize, 
                   const double argEquityPercent, 
                   const double argStopLoss, 
                   const double argFixedLotSize)
{
    if (argDynamicLotSize && argStopLoss > 0)
    {
        double RiskAmount = argAccountEquity * (argEquityPercent / 100),
               TickValue  = MarketInfo(argSymbol, MODE_TICKVALUE); // profit per pip
               
        if (Point == 0.001 || Point == 0.00001)
            TickValue *= 10;
            
        return ((RiskAmount / argStopLoss) / TickValue);
    }
    //else
    return argFixedLotSize;
}

void VerifyLotSize(double &argLotSize)
{
    if (argLotSize < MarketInfo(Symbol(), MODE_MINLOT))
        argLotSize = MarketInfo(Symbol(), MODE_MINLOT);
    else if (argLotSize > MarketInfo(Symbol(), MODE_MAXLOT))
        argLotSize = MarketInfo(Symbol(), MODE_MAXLOT);
        
    argLotSize = NormalizeDouble(argLotSize, MarketInfo(Symbol(), MODE_LOTSTEP) == 0.1 ? 1 : 2);
}

int OpenOrder(const string    argSymbol,
              const orderType argOperation,
              const double    argLotSize,
              const int       argSlippage,
              const double    argStopLoss,
              const double    argTakeProfit,
              const int       argMagicNumber,
                    int       argMaxOrderRetry = 1,
              const string    argComment = "Open Order")
{
    int Ticket = 0;
    
    while (Ticket <=0 && argMaxOrderRetry-- > 0 && (Ticket == -1 ? ErrorCheck(GetLastError()) : true))
    {
        WaitForTradeContextFree();
        Ticket = OrderSend(argSymbol, argOperation, argLotSize, 
                           MarketInfo(argSymbol, argOperation == T_BUY ? MODE_ASK : MODE_BID), 
                           argSlippage, argStopLoss, argTakeProfit, argComment, argMagicNumber, 0, Green);
    }
                           
    if (Ticket <= 0)
        HandleLastError();
       
    return Ticket;
}

bool CloseOrder(const string    argSymbol,
                const int       argTicketId,
                const orderType argTicketOperation,
                const int       argSlippage,
                      int       argMaxOrderRetry = 1)
{    
    if (OrderSelect(argTicketId, SELECT_BY_TICKET))
    {
        if (OrderCloseTime() == 0)
        {
            bool IsClosed = false;
        
            while (!IsClosed && argMaxOrderRetry-- > 0)
            {
                WaitForTradeContextFree();
                IsClosed = OrderClose(argTicketId, OrderLots(), 
                           MarketInfo(argSymbol, (argTicketOperation == T_BUY ? MODE_BID : MODE_ASK)), 
                           argSlippage, Red);
            }
            
            if (IsClosed)
                return true;
        }
        else
        {
            Alert(StringConcatenate("Ticket, ", argTicketId, "already closed!"));
            return false;
        }
        
    }
    
    HandleLastError();
        
    return false;
}

double CalcStopLoss(const orderType argOperation,
                    const double    argStopLoss,
                    const double    argPoint,
                    const double    argOpenPrice)
{   
    if (argStopLoss > 0)
        return argOpenPrice + argStopLoss * argPoint * (argOperation == T_BUY ? -1 : 1);
    //else
    return argStopLoss;
}

double CalcTakeProfit(const int    argOperation,
                      const double argTakeProfit,
                      const double argPoint,
                      const double argOpenPrice)
{
    if (argTakeProfit > 0)
        return argOpenPrice + argTakeProfit * argPoint * (argOperation == T_BUY ? 1 : -1);
    //else
    return argTakeProfit;
}

void AdjustToUpperStopLevel(const string argSymbol,
                            const double argUsePoint,
                            const int    argMinStopMargin,
                                  double &argValue)
{
    double StopLevel = MarketInfo(argSymbol, MODE_STOPLEVEL) * Point;
    
    double UpperStopLevel = MarketInfo(argSymbol, MODE_ASK) + StopLevel,
           MinStop = argMinStopMargin * argUsePoint;
    
    if (argValue > 0 && argValue < UpperStopLevel)
        argValue = UpperStopLevel + MinStop;
}

void AdjustToLowerStopLevel(const string argSymbol,
                            const double argUsePoint,
                            const int    argMinStopMargin,
                                  double &argValue)
{
    double StopLevel = MarketInfo(argSymbol, MODE_STOPLEVEL) * Point;
    
    double LowerStopLevel = MarketInfo(argSymbol, MODE_BID) - StopLevel,
           MinStop = argMinStopMargin * argUsePoint;
    
    if (argValue > 0 && argValue > LowerStopLevel)
        argValue = LowerStopLevel - MinStop;
}

bool AddStopLossTakeProfit(const int    argTicketId,
                           const double argOpenPrice,
                           const double argStopLoss,
                           const double argTakeProfit,
                                 int    argMaxOrderRetry = 1)
{
    if (argStopLoss > 0 || argTakeProfit > 0)
    {
        bool IsModified = false;
        
        while (!IsModified && argMaxOrderRetry-- > 0)
        {
            WaitForTradeContextFree();
            IsModified = OrderModify(argTicketId, argOpenPrice, argStopLoss, argTakeProfit, 0);
        }
    
        if (IsModified)
            return true;
        else
            HandleLastError();
    }
    
    return false;
}

bool BuyTrailingStop(const string argSymbol,
                     const int    argTicketId,
                     const int    argTrailingStop,
                     const int    argMinProfit,
                           int    argMaxOrderRetry = 1)
{
    if (OrderSelect(argTicketId, SELECT_BY_TICKET))
    {
        if (OrderCloseTime() == 0)
        {
            double MaxStopLoss = NormalizeDouble(MarketInfo(argSymbol, MODE_BID) - argTrailingStop * GetPipPoint(argSymbol),
                                                 (int)MarketInfo(OrderSymbol(), MODE_DIGITS));
                                                 
            double CurrentStop = NormalizeDouble(OrderStopLoss(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS));
            
            double PipsProfit = MarketInfo(argSymbol, MODE_BID) - OrderOpenPrice(),
                   MinProfit  = argMinProfit * GetPipPoint(argSymbol);
                   
            if (OrderType() == OP_BUY && CurrentStop < MaxStopLoss && PipsProfit >= MinProfit)
            {
                bool IsModified = false;
                
                while (!IsModified && argMaxOrderRetry-- > 0)
                {
                    WaitForTradeContextFree();
                    IsModified = OrderModify(OrderTicket(), OrderOpenPrice(), MaxStopLoss, OrderTakeProfit(), 0);
                }
            
                if (IsModified)
                    return true;
                else
                    HandleLastError();
            }
        }
        else
            Alert("Order ", argTicketId, " already closed! Can't set trailing stop!");
    }
    else
        HandleLastError();
        
    return false;
}

bool SellTrailingStop(const string argSymbol,
                     const int    argTicketId,
                     const int    argTrailingStop,
                     const int    argMinProfit,
                           int    argMaxOrderRetry = 1)
{
    if (OrderSelect(argTicketId, SELECT_BY_TICKET))
    {
        if (OrderCloseTime() == 0)
        {
            double MaxStopLoss = NormalizeDouble(MarketInfo(argSymbol, MODE_ASK) + argTrailingStop * GetPipPoint(argSymbol),
                                                 (int)MarketInfo(OrderSymbol(), MODE_DIGITS));
                                                 
            double CurrentStop = NormalizeDouble(OrderStopLoss(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS));
            
            double PipsProfit = OrderOpenPrice() - MarketInfo(argSymbol, MODE_ASK),
                   MinProfit  = argMinProfit * GetPipPoint(argSymbol);
                   
            if (OrderType() == OP_SELL && (CurrentStop > MaxStopLoss || CurrentStop == 0) && PipsProfit >= MinProfit)
            {
                bool IsModified = false;
                
                while (!IsModified && argMaxOrderRetry-- > 0)
                {
                    WaitForTradeContextFree();
                    IsModified = OrderModify(OrderTicket(), OrderOpenPrice(), MaxStopLoss, OrderTakeProfit(), 0);
                }
            
                if (IsModified)
                    return true;
                else
                    HandleLastError();
            }
        }
        else
            Alert("Order ", argTicketId, " already closed! Can't set trailing stop!");
    }
    else
        HandleLastError();
        
    return false;
}

bool WaitForTradeContextFree(const int argSleepMs = 10,
                                   int argMaxRetry = 100)
{
    while (argMaxRetry-- > 0)
    {
        if (IsTradeContextBusy())
            Sleep(argSleepMs);
        else
            return true;
    }
    
    Alert("Trade context busy!");
    
    return false;
}

bool ErrorCheck(int ErrorCode)
{
    switch (ErrorCode)
    {
        case 128: return true; // trade timeout
        case 136: return true; // off quotes
        case 138: return true; // requotes
        case 146: return true; // trade context busy
        default:  return false;
    }
    
    return false;
}

// debugging functions

void HandleLastError()
{
    int    ErrCode = GetLastError();
    string ErrDesc = ErrorDescription(ErrCode);
    
    Alert(StringConcatenate("Error ", ErrCode, " - ", ErrDesc)); 
}