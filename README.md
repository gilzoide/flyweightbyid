# flyweightbyid
A `-betterC` compatible Flyweight template based on explicitly named ids for [D](https://dlang.org/).

It is available as a [DUB package](https://code.dlang.org/packages/flyweightbyid)
and may be used directly as a [Meson subproject](https://mesonbuild.com/Subprojects.html)
or [wrap](https://mesonbuild.com/Wrap-dependency-system-manual.html).

Maintains two thread local or global arrays, one for identified objects, so that only one instance for each ID is loaded at a time, and another for reference counts or boolean loaded flags.
Uses automatic reference counting via copy constructor/postblit and destructor by default, but has an option for manually unloading.

Loading and unloading of instances is fully customizable by passing the right callables to template.

As a special case, one may supply a single id to Flyweight and achieve a Singleton pattern.


## Usage examples
```d
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

void example()
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
```

```d
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

void example2()
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
```
