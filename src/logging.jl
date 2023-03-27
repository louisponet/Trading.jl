function log_error(e; kwargs...)
    s = IOBuffer()
    showerror(s, e, catch_backtrace(); backtrace=true)
    errormsg = String(resize!(s.data, s.size))
    @error errormsg kwargs...
    return errormsg
end
