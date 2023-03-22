const QUEUE_LENGTH = 1024

mutable struct SeqLock{T}
    @atomic seq::Int
    v::T
    function SeqLock(v::T) where T
        new{T}(0, v)
    end
    function SeqLock{T}() where T
        out = new{T}()
        @atomic out.seq = 0
        return out
    end
end

@inline function store!(l::SeqLock, v)
    t = l.seq[] + 1
    @atomic :release l.seq = t
    t2 = t + 1
    l.v = v
    @atomic :release l.seq = t2
end

@inline function load(l::SeqLock)
    while true
        s1 = @atomic :acquire l.seq
        s1 & 1 == 1 && continue
        v = l.v
        s2 = @atomic :acquire l.seq
        s1 == s2 && return v
    end
end

mutable struct SPMCQueue{T}
    q::Vector{SeqLock{T}}
    write_id::Int
end
SPMCQueue{T}() where T = SPMCQueue{T}([SeqLock{T}() for i=1:QUEUE_LENGTH] , 0)

@inline function write!(q::SPMCQueue, v)
    @inbounds begin
        t = q.write_id + 1
        store!(q.q[mod1(t, QUEUE_LENGTH)], v)
        q.write_id = t
    end
end

@inline function read(q::SPMCQueue, i)
    @inbounds begin
        return i > q.write_id ? nothing : load(q.q[mod1(i, QUEUE_LENGTH)])
    end
end
