import Base: zero, +, -, /, *, sqrt, ^
@trait Indicator

@implement Is{Indicator} by zero(_) 
@implement Is{Indicator} by (+)(_, _) 
@implement Is{Indicator} by (-)(_, _) 
@implement Is{Indicator} by (*)(_, _) 
@implement Is{Indicator} by (/)(_, ::Int) 
@implement Is{Indicator} by (*)(_, ::AbstractFloat) 
@implement Is{Indicator} by (*)(::AbstractFloat, _) 
@implement Is{Indicator} by (*)(::Integer, _) 
@implement Is{Indicator} by (sqrt)(_) 
@implement Is{Indicator} by (^)(_, ::Int) 

