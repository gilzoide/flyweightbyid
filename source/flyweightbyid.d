import std.traits : isCallable;

private template joinNames(string[] names)
{
    private string _joinNames(string[] names)
    {
        string result;
        foreach (n; names)
        {
            result ~= n ~ ", ";
        }
        return result;
    }

    enum joinNames = _joinNames(names);
}

struct Flyweight(T, alias makeFunc, alias disposeFunc, Names...)
if (isCallable!makeFunc && isCallable!disposeFunc)
{
    static if (Names.length == 1 && !is(typeof(Names[0]) == string))
    {
        static if (is(Names[0] == enum))
        {
            import std.algorithm : map;
            import std.array : array;
            import std.conv : to;
            import std.traits : EnumMembers;
            private enum string[] names = [EnumMembers!(Names[0])].map!(to!string).array;
        }
        else
        {
            private enum string[] names = Names[0];
        }
    }
    else
    {
        private enum string[] names = [Names];
    }

    mixin("enum ID : uint "
        ~ "{"
            ~ joinNames!(names)
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

    /// Object ID, used for reference counting
    private ID id = ID.invalid;
    /// Object data
    T object;
    alias object this;

    private this(const ID id, const T object)
    {
        this.id = id;
        this.object = object;
    }

    this(ref return scope inout Flyweight other)
    {
        this.id = other.id;
        this.object = other.object;
        if (isValid)
        {
            incref(id);
        }
    }
    version (GNU)
    {
        this(this)
        {
            if (isValid)
            {
                incref(id);
            }
        }
    }

    ~this()
    {
        if (isValid)
        {
            unref(id);
        }
    }

    static private T[names.length] knownObjects;
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
        incref(id);
        return Flyweight(id, knownObjects[id]);
    }

    static void incref(ID id)
    in { assert(isValidID(id)); }
    out { assert(referenceCounts[id] > 0); }
    do
    {
        referenceCounts[id]++;
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
                disposeFunc(knownObjects[id]);
            }
        }
    }

    static bool isLoaded(ID id)
    in { assert(isValidID(id)); }
    do
    {
        return referenceCounts[id] > 0;
    }

    static foreach (name; names)
    {
        mixin("static Flyweight " ~ name ~ "() { return get(ID." ~ name ~ "); }");
    }
}

version (unittest)
{
    enum names = [
        "one",
        "two",
        "three",
    ];
    string makeName(uint id)
    {
        return id < names.length ? names[id] : null;
    }
    void disposeName(ref string name)
    {
        import std.stdio : writeln;
        writeln("Bye bye ", name);
        name = null;
    }
}

unittest
{
    // names from string[]
    alias NameFlyweight = Flyweight!(string, makeName, disposeName, names);
    NameFlyweight invalid;
    assert(!invalid.isValid);

    {
        assert(NameFlyweight.one == "one");
        assert(NameFlyweight.two == "two");
        assert(NameFlyweight.three == "three");
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

unittest
{
    // names from enum members
    enum ABC { A, B, C, D, None }
    alias ABCFlyweight = Flyweight!(string, makeName, disposeName, ABC);
    assert(__traits(hasMember, ABCFlyweight, "A"));
    assert(__traits(hasMember, ABCFlyweight.ID, "A"));
    assert(__traits(hasMember, ABCFlyweight, "B"));
    assert(__traits(hasMember, ABCFlyweight.ID, "B"));
    assert(__traits(hasMember, ABCFlyweight, "C"));
    assert(__traits(hasMember, ABCFlyweight.ID, "C"));
    assert(__traits(hasMember, ABCFlyweight, "D"));
    assert(__traits(hasMember, ABCFlyweight.ID, "D"));
    assert(__traits(hasMember, ABCFlyweight, "None"));
    assert(__traits(hasMember, ABCFlyweight.ID, "None"));
}

unittest
{
    // names passed directly
    alias ABCFlyweight = Flyweight!(string, makeName, disposeName, "A", "B", "C", "D", "None");
    assert(__traits(hasMember, ABCFlyweight, "A"));
    assert(__traits(hasMember, ABCFlyweight.ID, "A"));
    assert(__traits(hasMember, ABCFlyweight, "B"));
    assert(__traits(hasMember, ABCFlyweight.ID, "B"));
    assert(__traits(hasMember, ABCFlyweight, "C"));
    assert(__traits(hasMember, ABCFlyweight.ID, "C"));
    assert(__traits(hasMember, ABCFlyweight, "D"));
    assert(__traits(hasMember, ABCFlyweight.ID, "D"));
    assert(__traits(hasMember, ABCFlyweight, "None"));
    assert(__traits(hasMember, ABCFlyweight.ID, "None"));

    alias SingletonFlyweight = Flyweight!(string, makeName, disposeName, "instance");
    assert(__traits(hasMember, SingletonFlyweight, "instance"));
    assert(__traits(hasMember, SingletonFlyweight.ID, "instance"));
}
