# MESSAGING DICTIONARY SYNCHRONISATION

function collectmsgs(msgname::Symbol)
    @sync for j in Main.eval( :(keys($(msgname))) )
        @async begin
        val = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        Main.eval(Expr(:call, :setindex!, msgname, val, j)) 
        end
    end 
end

function collectmsgs(msgname::Symbol, msglocal::Dict)
    @sync for j in keys(msglocal)
        @async begin
        msglocal[j] = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        end
    end 
    msglocal
end

function collectmsgs(msgname::Symbol, pids::Array{Int64, 1})
    msglocal = Dict{Int64, Any}()
    @sync for j in pids
        @async begin
        msglocal[j] = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        end
    end 
    msglocal
end

function swapmsgs(pids::Array{Int64,1}, msgname::Symbol)
    @sync for pid in pids
         @async remotecall_wait(collectmsgs, pid, msgname)
    end   
end

function swapmsgs(msgname::Symbol)
    pids = workers()
    swapmsgs(pids, msgname) 
end


###  Manipulation utilities

function stitch(pids::Array{Int64,1}, expr_::Doable, cattype::Function)
    parts = reap(pids, expr_)
    reduce(cattype, [parts[k] for k in sort(collect(keys(parts)))])
end

function stitch(pid::Int64, expr_::Doable, cattype::Function)
    stitch([pid], expr_, cattype)
end

function stitch(pids::Array{Int64,1}, expr_::Doable)
    stitch(pids, expr_, vcat)
end

function stitch(pid::Int64, expr_::Doable)
    stitch([pid], expr_, vcat)
end

function stitch(expr_::Doable)
    pids = workers()
    stitch(pids, expr_, vcat)
end



