
# FINDING, STORING, LOADING DATA

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

function dictify(syms::Symbol...; mod=Main)
    Dict(s => eval(mod, s) for s in syms)
end

function save(fp::AbstractString, A::Any)
    f = open(fp, "w+")
    serialize(f, A)
    close(f)
end

function save(fp::AbstractString, syms::Symbol...)
    D = dictify(syms...)
    save(fp, D)
end

function load(fp)
    f = open(fp, "r")
    O = deserialize(f)
    close(f)
    O
end





# PERFMORMANCE TESTING

macro timeit(reps, expr)
   quote
       mean([@elapsed $expr for i in 1:$reps])
   end
end

function checksame(thing::Symbol)
    @assert length(Set(values(reap(thing))))==1
end




