
module ClusterUtils

export lookup, filterpaths, describepids, localpids
export getrepresentation, display
export Doable, sow, reap, reaprefs
export MessageDict
export collectmsgs, collectmsgsatpid, collectmsgsatmaster, swapmsgs

# FINDING DATA

function lookup(modname::Module, srchterm::Regex)
    vars = names(modname, true)
    indx = map((n)->ismatch(srchterm, string(n)), vars);
    vars[indx]
end


function filterpaths(dir, srch)
    srchr = Regex(srch)
    absdir = abspath(dir)
    fpths = readdir(absdir)
    matches = filter((name)->ismatch(srchr,name), fpths)
    map((nm)->absdir*"/"*nm, matches)
end

# PERFMORMANCE TESTING

macro timeit(reps, expr)
   quote
       mean([@elapsed $expr for i in 1:$reps])
   end
end


# DESCRIBING NETWORK TOPOLOGY

@doc """
Make a function that filters out strings matching the hostname of process 1.\n
""" ->
function makefiltermaster()
    master_node = strip(remotecall_fetch(readall, 1, `hostname`), '\n')
    function filtermaster(x)
        x != master_node
    end
    filtermaster
end


function describepids(pids; filterfn=(x)->true)

    # facts about the machines the processes run on
    machines = [strip(remotecall_fetch(readall, w, `hostname`), '\n') for w in pids]
    machine_names = sort!(collect(Set(machines)))
    machine_names = filter(filterfn, machine_names)
    num_machines = length(machine_names)

    # nominate a representative process for each machine, and define who it represents
    representative = zeros(Int64, num_machines)
    constituency = Dict()
    for (i,name) in enumerate(machine_names)
        constituency[i] = Int64[]
        for (j,machine) in enumerate(machines)
            if name==machine
                push!(constituency[i], pids[j])
                representative[i] = pids[j]
            end
        end
    end

    # assemble the groups of processes keyed by their representatives
    topo = Dict()
    for (i,p) in enumerate(representative)
        topo[p] = constituency[i]
    end

    topo
end

@doc """
Return information about the resources (pids) available to us grouped by the machine they are running on.\n
keyword argument: remote=0 (default) specifies remote machines; remote=1 the local machine; remote=2 all machines.\n 
length(topo) gives the number of unique nodes.\n
keys(topo) gives the id of a single process on each compute node.\n
values(topo) gives the ids of all processes running on each compute node.
""" ->
function describepids(; remote=0)
    pids = procs()
    if remote==0
        filterfn = makefiltermaster()
    elseif remote==1
        filtertrue = makefiltermaster()
        filterfn = (x)->!filtertrue(x)
    elseif remote==2
        filterfn=(x)->true
    end
    describepids(pids; filterfn=filterfn)
end

function localpids()
    topo = describepids(remote=1)
    topo[collect(keys(topo))[1]]
end


# REPRESENTATION OF SHARED ARRAYS THAT WORKS FOR SAs ON REMOTE HOSTS

function getrepresentation(S)
    buf = IOBuffer()
    td = TextDisplay(buf)
    Base.Multimedia.display(td, S)
    str = takebuf_string(buf)
    return str
end

function Base.display(S::SharedArray)
    validpid = minimum(S.pids)
    repr = @fetchfrom validpid getrepresentation(S)
    print_with_color(:bold, repr)
end



# FOR BROADCASTING VARIABLES

function sow(p::Int64, nm::Symbol, val; mod=Main)
    remotecall(Main.eval, p, mod, Expr(:(=), nm, val))
end

function sow(pids::Array{Int64, 1}, name::Symbol, value; mod=Main)
    refs = []
    @sync for p in pids
        @async push!(refs, sow(p, name, value; mod=mod))
    end
    refs
end

function sow(name::Symbol, value; mod=Main)
    pids = workers()
    sow(pids, name, value; mod=mod)
end

# HARVESTING VALUES OR REFERENCES FROM REMOTES

Doable = Union{Symbol, Expr}

function reap(pids::Array{Int64, 1}, doable::Doable; callstyle=remotecall_fetch, returntype=Any)
    results = Dict{Int64, returntype}()
    @sync for k in pids
        @async results[k] = callstyle(Main.eval, k, doable)
    end
    results
end

function reap(doable::Doable; calltype=remotecall_fetch, returntype=Any)
    pids = workers()
    reap(pids, doable; calltype=calltype, returntype=returntype) 
end

function reap(pid::Int64, doable::Doable; calltype=remotecall_fetch, returntype=Any)
    pids = [pid];
    reap(pids, doable; calltype=calltype, returntype=returntype) 
end

function reaprefs(pids, doable::Doable; returntype=Any)
    reap(pids, doable; calltype=remotecall, returntype=returntype) 
end

# MESSAGING DICTIONARIES

type MessageDict
   pids::Array{Int64,1}
   msgs::Dict{Int64,Any} 
end

#initialise a default msg
function MessageDict()
   pids = workers()
   msgs = Dict([k => 0 for k in pids])
   MessageDict(pids, msgs)
end

#initialise from a dict
function MessageDict(D::Dict)
   pids = collect(keys(D))
   msgs = copy(D)
   MessageDict(pids, msgs)
end

#initialise with pids and zeros of type X
function MessageDict(pids::Array{Int64, 1}, X::AbstractArray)
   z = zero(X)
   msgs = Dict([k => copy(z) for k in pids])
   MessageDict(pids, msgs)
end

#getting and setting indices operates on the M.msgs attribute
function Base.getindex(M::MessageDict, index)
   getindex(M.msgs, index)
end

function Base.setindex!(M::MessageDict, value, index)
   setindex!(M.msgs, value, index)
end

#make the display unmessy
function Base.display(M::MessageDict)
   Base.display(typeof(M))
   Base.display(M.msgs)
end




#MESSAGING DICTIONARY SYNCHRONISATION

function collectmsgs(msgname::Symbol)
    @sync for j in Main.eval(:($(msgname).pids))
        @async begin
        val = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        Main.eval(Expr(:call, :setindex!, msgname, val, j)) 
        end
    end 
end

function collectmsgssafe(msgname::Symbol)
    if(isdefined(msgname))
    @sync for j in Main.eval(:($(msgname).pids))
        @async begin
        val = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        Main.eval(Expr(:call, :setindex!, msgname, val, j)) 
        end
    end 
    end
end

function collectmsgsatmaster(msgname::Symbol, msglocal::MessageDict)
    @sync for j in msglocal.pids
        @async begin
        msglocal[j] = remotecall_fetch(Main.eval, j, Expr(:call, :getindex, msgname, j))
        #Main.eval(Expr(:call, :setindex!, :(msglocal), val, j)) 
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



end
