struct StallException <: Exception
    e
end

function Base.showerror(io::IO, err::StallException, args...)
    print(io, "StallException:")
    showerror(io, err.e, args...)
end

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
            if !($err.task.exception isa InterruptException)
                rethrow($err)
            end
        end
    end)
end


