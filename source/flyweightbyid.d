import std.traits : isCallable;

private template normalizeName(string name)
{
    private string _normalizeName()
    {
        import std.ascii : isAlphaNum, isDigit;
        string result;
        foreach (c; name)
        {
            result ~= (isAlphaNum(c) || c == '_') ? c : '_';
        }
        if (isDigit(result[0]))
        {
            result = '_' ~ result;
        }
        return result;
    }

    enum normalizeName = _normalizeName();
}

private template joinNames(string[] names)
{
    private string _joinNames()
    {
        string result;
        static foreach (n; names)
        {
            result ~= normalizeName!n ~ ", ";
        }
        return result;
    }

    enum joinNames = _joinNames();
}

enum FlyweightOptions
{
    none = 0,
    gshared = 1 << 0,
}

struct Flyweight(T, alias makeFunc, alias disposeFunc, alias _names, const FlyweightOptions options = FlyweightOptions.none)
if (isCallable!makeFunc && isCallable!disposeFunc)
{
    static if (is(_names == enum))
    {
        import std.algorithm : map;
        import std.array : array;
        import std.conv : to;
        import std.traits : EnumMembers;
        private enum string[] names = [EnumMembers!(_names)].map!(to!string).array;
    }
    else static if (is(typeof(_names) == string))
    {
        private enum string[] names = [_names];
    }
    else
    {
        private enum string[] names = _names;
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

    static if (options & FlyweightOptions.gshared)
    {
        __gshared private T[names.length] knownObjects;
        __gshared private uint[names.length] referenceCounts = 0;
    }
    else
    {
        static private T[names.length] knownObjects;
        static private uint[names.length] referenceCounts = 0;
    }

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
        mixin("static Flyweight " ~ normalizeName!name ~ "() { return get(ID." ~ normalizeName!name ~ "); }");
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
    alias ABCFlyweight = Flyweight!(string, makeName, disposeName, ["A", "B", "C", "D", "None"]);
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

    alias SingletonFlyweight = Flyweight!(string, makeName, disposeName, "instance", FlyweightOptions.gshared);
    assert(__traits(hasMember, SingletonFlyweight, "instance"));
    assert(__traits(hasMember, SingletonFlyweight.ID, "instance"));
}

unittest
{
    // names with invalid identifier chars
    alias MyFlyweight = Flyweight!(string, makeName, disposeName, ["First ID", "Second!", "123"]);
    assert(__traits(hasMember, MyFlyweight, "First_ID"));
    assert(__traits(hasMember, MyFlyweight.ID, "First_ID"));
    assert(__traits(hasMember, MyFlyweight, "Second_"));
    assert(__traits(hasMember, MyFlyweight.ID, "Second_"));
    assert(__traits(hasMember, MyFlyweight, "_123"));
    assert(__traits(hasMember, MyFlyweight.ID, "_123"));
}
