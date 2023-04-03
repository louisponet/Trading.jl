struct StallException <: Exception
    e
end

function Base.showerror(io::IO, err::StallException, args...)
    print(io, "StallException:")
    showerror(io, err.e, args...)
end

"""
    @timeout

Macro to create a self interrupting task after a specified number of seconds.
If the task finished before completing nothing happens.

# Example:
```julia
@timeout 30 sleep(31) # Will interrupt the sleeping after 30 seconds 
```
"""
macro timeout(seconds, expr, err_expr=:(nothing))
    tsk        = gensym("tsk")
    start_time = gensym("start_time")
    curt       = gensym("curt")
    timer      = gensym("timer")
    err        = gensym("err")
    
    esc(quote
        $tsk = @task $expr
        schedule($tsk)
        
        $start_time = time()
        
        $curt = time()
        Base.Timer(0.001, interval=0.001) do $timer
            if $tsk === nothing || istaskdone($tsk)
                close($timer)
            else
                $curt = time()
                if $curt - $start_time > $seconds
                    Base.throwto($tsk, InterruptException())
                end
            end
        end
        try
            fetch($tsk)
        catch $err
            if $err.task.exception isa InterruptException
                RemoteHPC.log_error(RemoteHPC.StallException($err))
                $err_expr
            else
                rethrow($err)
            end
        end
    end)
end

"""
    @stoppable

Macro to create an interruptable task based on the boolean value of the specified variable.

# Example:
```julia
stop = false
@async @stoppable stop while true
    println("not stopped")
    sleep(1)
end

stop = true # will interrupt the printing
```
"""
macro stoppable(stop, expr)
    tsk        = gensym("tsk")
    timer      = gensym("timer")
    err = gensym("err")
    
    esc(quote
        $tsk = @task $expr
        schedule($tsk)
        
        Base.Timer(0.001, interval=0.001) do $timer
            if $tsk === nothing || istaskdone($tsk)
                close($timer)
            elseif $stop
                Base.throwto($tsk, InterruptException())
            end
        end
        try
            fetch($tsk)
        catch $err
            if !($err isa InterruptException) || !($err.task.exception isa InterruptException)
                rethrow($err)
            end
        end
    end)
end


function log_error(e; kwargs...)
    s = IOBuffer()
    showerror(s, e, catch_backtrace(); backtrace=true)
    errormsg = String(resize!(s.data, s.size))
    @error errormsg kwargs...
    return errormsg
end
