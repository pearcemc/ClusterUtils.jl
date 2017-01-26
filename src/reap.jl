
# FOR BROADCASTING VARIABLES

Doable = Union{Symbol, Expr}

function yieldfirst(todo::Doable) #required while bug 14445 still around
    return :(yield(); $todo)
end

function sow(pid::Int64, name::Doable, value; mod=Main, callstyle=remotecall_wait)
    todo = Expr(:(=), name, value) 
    #callstyle(Main.eval, pid, mod, yieldfirst(todo))
    callstyle(Main.eval, pid, mod, todo)
end

function sow(pids::Array{Int64, 1}, name::Doable, value; mod=Main, callstyle=remotecall_wait)
    refs = Dict{Int64, Any}()
    @sync for p in pids
        @async begin 
            rref = sow(p, name, value; mod=mod, callstyle=callstyle)
            refs[p] = rref
        end 
    end
    refs
end

function sow(name::Doable, value; mod=Main, callstyle=remotecall_wait)
    pids = workers()
    sow(pids, name, value; mod=mod, callstyle=callstyle)
end

# HARVESTING VALUES OR REFERENCES FROM REMOTES

function reap(pids::Array{Int64, 1}, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    results = Dict{Int64, returntype}()
    #todo = yieldfirst(doable) 
    @sync for pid in pids
        @async results[pid] = callstyle(Main.eval, pid, doable)
    end
    results
end

function reap(doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    pids = workers()
    reap(pids, doable; callstyle=callstyle, returntype=returntype) 
end

function reap(pid::Int64, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    pids = [pid];
    reap(pids, doable; callstyle=callstyle, returntype=returntype) 
end

function reaprefs(pids, doable::Doable; returntype=Any)
    reap(pids, doable; callstyle=remotecall_fetch, returntype=returntype) 
end




