import std.traits : isCallable;

struct Flyweight(T, alias makeFunc, alias disposeFunc, alias names)
if (isCallable!makeFunc && isCallable!disposeFunc)
{
    import std.algorithm : map;
    import std.string : join;
    mixin("enum ID : uint "
        ~ "{"
            ~ names.map!((string n) { return n ~ ","; }).join(" ")
            ~ "invalid"
        ~ "}"
    );
    /// Verify if ID is a valid object ID
    static bool isValidID(ID id)
    {
        return id < names.length;
    }
    /// Verify if this is a valid Flyweight object
    bool isValid() const
    {
        return isValidID(id);
    }

    /// Pointer to the object data
    T* object = null;
    /// Object ID, used for reference counting
    private ID id = ID.invalid;
    alias object this;

    ~this()
    {
        if (isValid)
        {
            unref(id);
        }
    }

    static private T*[names.length] knownObjects = null;
    static private uint[names.length] referenceCounts = 0;

    static Flyweight get(ID id)
    in { assert(isValidID(id)); }
    out { assert(referenceCounts[id] > 0); }
    do
    {
        if (referenceCounts[id] == 0)
        {
            knownObjects[id] = makeFunc(id);
        }
        referenceCounts[id]++;
        typeof(return) obj = {
            id: id,
            object: knownObjects[id],
        };
        return obj;
    }

    static void unref(ID id)
    in { assert(isValidID(id)); }
    do
    {
        if (referenceCounts[id] > 0)
        {
            referenceCounts[id]--;
            if (referenceCounts[id] == 0)
            {
                if (knownObjects[id])
                {
                    disposeFunc(knownObjects[id]);
                }
                knownObjects[id] = null;
            }
        }
    }

    static bool isLoaded(ID id)
    in { assert(isValidID(id)); }
    do
    {
        return referenceCounts[id] > 0;
    }

    static foreach (i, name; names)
    {
        import std.format : format;
        mixin(format!"static Flyweight %s() { return get(ID.%s); }"(name, name));
    }
}

version (unittest)
{
    enum names = [
        "one",
        "two",
        "three",
    ];
    string* makeName(uint id)
    {
        return &names[id];
    }
    void disposeName(string* name)
    {
        import std.stdio : writeln;
        writeln("Bye bye ", *name);
    }
}

unittest
{
    alias NameFlyweight = Flyweight!(string, makeName, disposeName, names);
    NameFlyweight invalid;
    assert(!invalid.isValid);

    {
        assert(*NameFlyweight.one == "one");
        assert(*NameFlyweight.two == "two");
        assert(*NameFlyweight.three == "three");
    }

    {
        const auto one1 = NameFlyweight.one;
        const auto one2 = NameFlyweight.one;
        const auto one3 = NameFlyweight.one;
        assert(NameFlyweight.isLoaded(NameFlyweight.ID.one));
        assert(one1.object is one2.object);
        assert(one2.object is one3.object);
        assert(one1.object is one3.object);
    }

    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.one));
    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.two));
    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.three));
}
