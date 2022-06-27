import Base: zero, +, -, /
@trait Indicator

@implement Is{Indicator} by zero(_) 
@implement Is{Indicator} by (+)(_, _) 
@implement Is{Indicator} by (-)(_, _) 
@implement Is{Indicator} by (/)(_, ::Int) 

