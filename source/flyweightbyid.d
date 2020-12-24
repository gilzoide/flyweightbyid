import std.traits : isCallable;

/// Options for Flyweight instances.
enum FlyweightOptions
{
    /// Default options: Thread local storage, automatic reference counting.
    none = 0,
    /// Use global storage instead of thread local storage.
    gshared = 1 << 0,
    /// Don't count references.
    noReferenceCount = 1 << 1,
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
    private enum gshared = options & FlyweightOptions.gshared;
    private enum shouldCountReferences = !(options & FlyweightOptions.noReferenceCount);

    mixin("enum ID : uint"
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

    /// Private so that Flyweight instances with valid IDs are created by `get` and copy constructors only.
    private this(const ID id, const T object)
    {
        this.id = id;
        this.object = object;
    }

    static if (gshared)
    {
        /// Global array of known objects.
        __gshared private T[names.length] knownObjects;
        static if (shouldCountReferences)
        {
            /// Global array of reference counts.
            __gshared private uint[names.length] referenceCounts = 0;
        }
        else
        {
            /// Global array of booleans for marking loaded objects.
            __gshared private bool[names.length] loadedFlags = false;
        }
    }
    else
    {
        /// Thread local array of known objects.
        static private T[names.length] knownObjects;
        static if (shouldCountReferences)
        {
            /// Thread local array of reference counts.
            static private uint[names.length] referenceCounts = 0;
        }
        else
        {
            /// Thread local array of booleans for marking loaded objects.
            static private bool[names.length] loadedFlags = false;
        }
    }

    static if (shouldCountReferences)
    {
        /// Copy constructor with automatic reference counting.
        this(ref return scope inout Flyweight other)
        {
            this.id = other.id;
            this.object = other.object;
            if (isValid)
            {
                incref(id);
            }
        }

        version (D_BetterC) {}
        else
        {
            /// Post-blit with automatic reference counting.
            this(this) @nogc nothrow
            {
                if (isValid)
                {
                    incref(id);
                }
            }
        }

        /// Destructor with automatic reference counting.
        ~this()
        {
            if (isValid)
            {
                unref(id);
            }
        }

        /// Manually increment reference.
        static void incref(ID id) @nogc nothrow
        in { assert(isValidID(id)); }
        out { assert(referenceCounts[id] > 0); }
        do
        {
            referenceCounts[id]++;
        }

        /// Manually decrement reference.
        static void unref(ID id)
        in { assert(isValidID(id)); }
        do
        {
            if (isLoaded(id))
            {
                referenceCounts[id]--;
                if (referenceCounts[id] == 0)
                {
                    disposeFunc(knownObjects[id]);
                }
            }
        }
    }

    /// Get the Flyweight instance for object identified by `id`, constructing it if not loaded yet.
    static Flyweight get(ID id)
    in { assert(isValidID(id)); }
    out { assert(isLoaded(id)); }
    do
    {
        if (!isLoaded(id))
        {
            knownObjects[id] = makeFunc(id);
            static if (!shouldCountReferences) loadedFlags[id] = true;
        }
        static if (shouldCountReferences) incref(id);
        return Flyweight(id, knownObjects[id]);
    }

    /// Returns if Flyweight identified by `id` is loaded of not.
    static bool isLoaded(ID id) @nogc nothrow
    in { assert(isValidID(id)); }
    do
    {
        static if (shouldCountReferences)
        {
            return referenceCounts[id] > 0;
        }
        else
        {
            return loadedFlags[id];
        }
    }

    /// If Flyweight identified by `id` is loaded, manually unload it and reset reference count/loaded flag.
    static void unload(ID id)
    in { assert(isValidID(id)); }
    do
    {
        if (isLoaded(id))
        {
            disposeFunc(knownObjects[id]);
            static if (shouldCountReferences)
            {
                referenceCounts[id] = 0;
            }
            else
            {
                loadedFlags[id] = false;
            }
        }
    }

    /// Manually unload all loaded instances and reset reference counts/loaded flags.
    static void unloadAll()
    out {
        import std.traits : EnumMembers;
        foreach (id; EnumMembers!ID)
        {
            assert(!isLoaded(id));
        }
    }
    do
    {
        import std.traits : EnumMembers;
        foreach (id; EnumMembers!ID)
        {
            unload(id);
        }
    }

    static foreach (name; names)
    {
        mixin("static Flyweight " ~ normalizeName!name ~ "() { return get(ID." ~ normalizeName!name ~ "); }");
    }
}

// Private compile-time helpers
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
    // name passed directly
    alias SingletonFlyweight = Flyweight!(string, makeName, disposeName, "instance", FlyweightOptions.gshared);
    assert(__traits(hasMember, SingletonFlyweight, "instance"));
    assert(__traits(hasMember, SingletonFlyweight.ID, "instance"));
}

unittest
{
    // names with invalid enum identifiers
    alias MyFlyweight = Flyweight!(string, makeName, disposeName, ["First ID", "Second!", "123"]);
    assert(__traits(hasMember, MyFlyweight, "First_ID"));
    assert(__traits(hasMember, MyFlyweight.ID, "First_ID"));
    assert(__traits(hasMember, MyFlyweight, "Second_"));
    assert(__traits(hasMember, MyFlyweight.ID, "Second_"));
    assert(__traits(hasMember, MyFlyweight, "_123"));
    assert(__traits(hasMember, MyFlyweight.ID, "_123"));
}

unittest
{
    // no reference counting
    alias ABCFlyweight = Flyweight!(string, makeName, disposeName, ["A", "B", "C"], FlyweightOptions.noReferenceCount);
    {
        auto a = ABCFlyweight.A;
        assert(ABCFlyweight.isLoaded(ABCFlyweight.ID.A));
    }
    assert(ABCFlyweight.isLoaded(ABCFlyweight.ID.A));
    assert(!ABCFlyweight.isLoaded(ABCFlyweight.ID.B));
    auto a = ABCFlyweight.A;
    ABCFlyweight.unload(ABCFlyweight.ID.A);
    assert(!ABCFlyweight.isLoaded(ABCFlyweight.ID.A));
}
