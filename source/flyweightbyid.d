module flyweightbyid;

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

/**
 * Flyweight template.
 *
 * Params:
 *   T = Instance type
 *   makeFunc = Callable that receives ID as argument and returns `T`
 *   disposeFunc = Callable that receives `ref T` instance to unload it
 *   idNames = Enum or string[] with known IDs
 *   options = Flyweight options
 */
struct Flyweight(T, alias makeFunc, alias disposeFunc, alias idNames, const FlyweightOptions options = FlyweightOptions.none)
if (isCallable!makeFunc && isCallable!disposeFunc)
{
    import std.conv : to;
    import std.range : isInputRange;
    import std.traits : EnumMembers;
    static if (is(idNames == enum))
    {
        private enum string[] names = [EnumMembers!(idNames)].to!(string[]);
    }
    else static if (is(typeof(idNames) : string))
    {
        private enum string[] names = [idNames];
    }
    else
    {
        private enum string[] names = idNames.to!(string[]);
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
    private this(const ID id, T object)
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
        this(ref return scope inout Flyweight other) inout
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
            /// Postblit with automatic reference counting.
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

    /// Returns whether there are any Flyweight instances loaded.
    static bool isAnyLoaded() @nogc nothrow
    {
        import std.algorithm : any;
        static if (shouldCountReferences)
        {
            return any!"a > 0"(referenceCounts[]);
        }
        else
        {
            return any(loadedFlags[]);
        }
    }

    /// If Flyweight identified by `id` is loaded, manually unload it and reset reference count/loaded flag.
    static void unload(ID id)
    in { assert(isValidID(id)); }
    out { assert(!isLoaded(id)); }
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
        foreach (id; EnumMembers!(ID)[0 .. $-1])
        {
            assert(!isLoaded(id));
        }
        assert(!isAnyLoaded);
    }
    do
    {
        foreach (id; EnumMembers!(ID)[0 .. $-1])
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
        assert(NameFlyweight.isAnyLoaded());
    }

    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.one));
    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.two));
    assert(!NameFlyweight.isLoaded(NameFlyweight.ID.three));
    assert(!NameFlyweight.isAnyLoaded());
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
    ABCFlyweight.unloadAll();
}

version (unittest)
{
    // README example
    import flyweightbyid;

    // Flyweight for instances of `Image*`, loaded by `loadImage` and unloaded by `unloadImage`
    // IDs and getter names are taken from `imageFileNames` slice
    alias ImageFlyweight = Flyweight!(
        Image*,
        loadImage,
        unloadImage,
        imageFileNames,
        /+, FlyweightOptions.none /+ (the default) +/ +/
    );

    // Some file names that should be loaded only once
    enum imageFileNames = [
        "img1.png",
        "subdir/img2.png",
    ];
    // Image struct, with a pointer to the data, dimensions, member functions, etc...
    struct Image {
        void draw() const
        {
            // ...
        }
        // ...
        ~this()
        {
            import std.stdio : writeln;
            writeln("bye bye");
        }
    }

    // Function that loads an Image from file
    Image* loadImage(uint id)
    {
        auto filename = imageFileNames[id];
        Image* img = new Image;
        // ...
        return img;
    }
    // Function to unload the images
    void unloadImage(ref Image* img)
    {
        // ...
        destroy(img);
    }
}
unittest
{
    // Flyweight identified by `ID.img1_png` is constructed by calling `loadImage(0)`
    // Notice how invalid identifier characters are replaced by underscores
    ImageFlyweight image1 = ImageFlyweight.get(ImageFlyweight.ID.img1_png);
    assert(ImageFlyweight.isLoaded(ImageFlyweight.ID.img1_png));

    // `img1_png` is an alias for getting the "img1.png" instance,
    // `subdir_img2_png` for "subdir/img2.png" and so on
    auto also_image1 = ImageFlyweight.img1_png;

    // `also_image1` contains the same instance as `image1`, as it is already loaded
    assert(also_image1 is image1);

    {
        // `ID.subdir_img2_png` is constructed by `loadImage(1)`
        ImageFlyweight image2 = ImageFlyweight.subdir_img2_png;

        // ImageFlyweight instance is a proxy (by means of `alias this`)
        // for the loaded `Image*` instance, so member functions, fields and
        // others work like expected
        image2.draw();

        // If `FlyweightOptions.noReferenceCount` is NOT passed to template (default),
        // references are automatically counted and content is unloaded if reference
        // count reaches 0. Pass them by value for automatic reference counting
        ImageFlyweight also_image2 = image2;

        assert(ImageFlyweight.isLoaded(ImageFlyweight.ID.subdir_img2_png));
        // subdir_img2_png gets unloaded
    }
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.subdir_img2_png));

    // It is possible to manually unload one or all instances, be careful to not access them afterwards!
    ImageFlyweight.unload(ImageFlyweight.ID.img1_png);
    ImageFlyweight.unloadAll();
    // It is safe to call unload more than once, so when `image1` and `also_image1`
    // are destroyed, nothing happens
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.img1_png));
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.subdir_img2_png));
}

version (unittest)
{
    // README example
    import flyweightbyid;

    // Config singleton, using global storage and not reference counted
    alias ConfigSingleton = Flyweight!(
        Config*,
        loadConfig,
        unloadConfig,
        "instance",
        FlyweightOptions.gshared | FlyweightOptions.noReferenceCount
    );

    // Configuration structure
    struct Config
    {
        // ...
    }
    Config* loadConfig(uint)
    {
        return new Config;
    }
    void unloadConfig(ref Config* c)
    {
        destroy(c);
    }
}
unittest
{
    assert(!ConfigSingleton.isLoaded(ConfigSingleton.ID.instance));
    {
        // Get Config instance
        auto config = ConfigSingleton.instance;

        auto also_config = ConfigSingleton.get(ConfigSingleton.ID.instance);
        assert(also_config is config);

        assert(ConfigSingleton.isLoaded(ConfigSingleton.ID.instance));
    }
    // ConfigSingleton is not reference counted, so it is still loaded
    assert(ConfigSingleton.isLoaded(ConfigSingleton.ID.instance));
    ConfigSingleton.unloadAll();
    assert(!ConfigSingleton.isLoaded(ConfigSingleton.ID.instance));
}
