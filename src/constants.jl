const EXCHS = Dict(
    "A" => "NYSE American (AMEX)",
    "B" => "NASDAQ OMX BX",
    "C" => "National Stock Exchange",
    "D" => "FINRA ADF",
    "E" => "Market Independent",
    "H" => "MIAX",
    "I" => "International Securities Exchange",
    "J" => "Cboe EDGA",
    "K" => "Cboe EDGX",
    "L" => "Long Term Stock Exchange",
    "M" => "Chicago Stock Exchange",
    "N" => "New York Stock Exchange",
    "P" => "NYSE Arca",
    "Q" => "NASDAQ OMX",
    "S" => "NASDAQ Small Cap",
    "T" => "NASDAQ Int",
    "U" => "Members Exchange",
    "V" => "IEX",
    "W" => "CBOE",
    "X" => "NASDAQ OMX PSX",
    "Y" => "Cboe BYX",
    "Z" => "Cboe BZX",
)

const CTS_CONDS = Dict(
    " " => "Regular Sale",
    "B" => "Average Price Trade",
    "C" => "Cash Trade (Same Day Clearing)",
    "E" => "Automatic Execution",
    "F" => "Inter-market Sweep Order",
    "H" => "Price Variation Trade",
    "I" => "Odd Lot Trade",
    "K" => "Rule 127 (NYSE only) or Rule 155 (NYSE MKT only)",
    "L" => "Sold Last (Late Reporting)",
    "M" => "Market Center Official Close",
    "N" => "Next Day Trade (Next Day Clearing)",
    "O" => "Market Center Opening Trade",
    "P" => "Prior Reference Price",
    "Q" => "Market Center Official Open",
    "R" => "Seller",
    "T" => "Extended Hours Trade",
    "U" => "Extended Hours Sold (Out Of Sequence)",
    "V" => "Contingent Trade",
    "X" => "Cross Trade",
    "Z" => "Sold (Out Of Sequence) ",
    "4" => "Derivatively Priced",
    "5" => "Market Center Reopening Trade",
    "6" => "Market Center Closing Trade",
    "7" => "Qualified Contingent Trade",
    "8" => "Reserved",
    "9" => "Corrected Consolidated Close Price as per Listing Market",
)

const UTDF_CONDS = Dict(
    "@" => "Regular Sale",
    "R" => "Seller",
    "A" => "Acquisition",
    "S" => "Split Trade",
    "B" => "Bunched Trade",
    "T" => "Form T",
    "C" => "Cash Sale",
    "U" => "Extended trading hours (Sold Out of Sequence)",
    "D" => "Distribution",
    "V" => "Contingent Trade",
    "E" => "Placeholder",
    "W" => "Average Price Trade",
    "F" => "Intermarket Sweep",
    "X" => "Cross Trade",
    "G" => "Bunched Sold Trade",
    "Y" => "Yellow Flag Regular Trade",
    "H" => "Price Variation Trade",
    "Z" => "Sold (out of sequence)",
    "I" => "Odd Lot Trade",
    "1" => "Stopped Stock (Regular Trade)",
    "K" => "Rule 155 Trade (AMEX)",
    "4" => "Derivatively priced",
    "L" => "Sold Last",
    "5" => "Re-Opening Prints",
    "M" => "Market Center Official Close",
    "6" => "Closing Prints",
    "N" => "Next Day",
    "7" => "Qualified Contingent Trade (QCT)",
    "O" => "Opening Prints",
    "8" => "Placeholder For 611 Exempt",
    "P" => "Prior Reference Price",
    "9" => "Corrected Consolidated Close (per listing market)",
    "Q" => "Market Center Official Open",
)

const CQS_CONDS = Dict(
    "A" => "Slow Quote Offer Side",
    "B" => "Slow Quote Bid Side",
    "E" => "Slow Quote LRP Bid Side",
    "F" => "Slow Quote LRP Offer Side",
    "H" => "Slow Quote Bid And Offer Side",
    "O" => "Opening Quote",
    "R" => "Regular Market Maker Open",
    "W" => "Slow Quote Set Slow List",
    "C" => "Closing Quote",
    "L" => "Market Maker Quotes Closed",
    "U" => "Slow Quote LRP Bid And Offer",
    "N" => "Non Firm Quote",
    "4" => "On Demand Intra Day Auction",
)

const UQDF_CONDS = Dict(
    "A" => "Manual Ask Automated Bid",
    "B" => "Manual Bid Automated Ask",
    "F" => "Fast Trading",
    "H" => "Manual Bid And Ask",
    "I" => "Order Imbalance",
    "L" => "Closed Quote",
    "N" => "Non Firm Quote",
    "O" => "Opening Quote Automated",
    "R" => "Regular Two Sided Open",
    "U" => "Manual Bid And Ask Non Firm",
    "Y" => "No Offer No Bid One Sided Open",
    "X" => "Order Influx",
    "Z" => "No Open No Resume",
    "4" => "On Demand Intra Day Auction",
)

