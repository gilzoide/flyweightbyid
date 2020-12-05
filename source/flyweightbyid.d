import std.traits : isCallable;

struct Flyweight(T, string[] names, alias makeFunc, alias disposeFunc)
if (isCallable!makeFunc && isCallable!disposeFunc)
{
    /// The ID type, suitable for indexing arrays
    alias ID = uint;
    //mixin("enum ID : uint {"
        //~ 
    //enum ID2
    //{
        //static foreach (name; names)
        //{
            //mixin(name ~ ",");
        //}
    //}
    /// Sentinel value for a surely unknown ID
    enum unknownID = ID.max;
    /// Verify if ID is a known object ID
    static bool isKnownID(ID id)
    {
        return id < names.length;
    }

    /// Pointer to the object data
    T* object = null;
    /// Object ID, used for reference counting
    private ID id = unknownID;
    alias object this;

    ~this()
    {
        if (isKnownID(id))
        {
            unref(id);
        }
    }

    static private T*[names.length] knownObjects = null;
    static private uint[names.length] referenceCounts = 0;

    static Flyweight get(ID id)
    in { assert(isKnownID(id)); }
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
    in { assert(isKnownID(id)); }
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
    in { assert(isKnownID(id)); }
    do
    {
        return referenceCounts[id] > 0;
    }

    static foreach (i, name; names)
    {
        import std.format : format;
        mixin(format!"static Flyweight %s() { return get(%s); }"(name, i));
    }
}

version (unittest)
{
    enum string[] names = ["one", "two", "three"];
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
    alias NameFlyweight = Flyweight!(string, names, makeName, disposeName);

    {
        assert(*NameFlyweight.one == "one");
        assert(*NameFlyweight.two == "two");
        assert(*NameFlyweight.three == "three");
    }

    {
        const auto one1 = NameFlyweight.one;
        const auto one2 = NameFlyweight.one;
        const auto one3 = NameFlyweight.one;
        assert(NameFlyweight.isLoaded(0));
        assert(one1.object is one2.object);
        assert(one2.object is one3.object);
        assert(one1.object is one3.object);
    }

    assert(!NameFlyweight.isLoaded(0));
    assert(!NameFlyweight.isLoaded(1));
    assert(!NameFlyweight.isLoaded(2));
}
