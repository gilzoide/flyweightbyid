# flyweightbyid
A `-betterC` compatible Flyweight template based on explicitly named ids for [D](https://dlang.org/).

Maintains two thread local or global arrays, one for identified objects, so that only one instance for each ID is loaded at a time, and another for reference counts or boolean loaded flags.
Uses automatic reference counting via copy constructors/post-blits and destructors by default, but has an option for manually unloading.

Loading and unloading of instances is fully customizable by passing the right callables to template.


## Usage
```d
import flyweightbyid;

// Some file names that should be loaded only once at a time
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

alias ImageFlyweight = Flyweight!(Image*, loadImage, unloadImage, imageFileNames /+, FlyweightOptions.none /+ (the default) +/ +/);

void example()
{
    {
        // `img1_png` is an alias for getting the "img1.png" instance
        // and is constructed by calling `loadImage(0)`
        // Notice how invalid identifier characters are replaced by underscores
        ImageFlyweight image1 = ImageFlyweight.img1_png;
        assert(ImageFlyweight.isLoaded(ImageFlyweight.ID.img1_png));

        // ImageFlyweight instance is a proxy (by means of `alias this`)
        // for the loaded `Image*` instance, so member functions, fields and
        // others work like expected
        image1.draw();

        // If `FlyweightOptions.noReferenceCount` is NOT passed to template (default),
        // references are automatically counted and content is unloaded if reference
        // count reaches 0. Pass them by value for automatic reference counting
        ImageFlyweight also_image1 = image1;

        // img1_png gets unloaded
    }
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.img1_png));

    // `image2` is constructed by `loadImage(1)`
    auto image2 = ImageFlyweight.subdir_img2_png;
    // `also_image2` contains the same instance, as it is already loaded
    auto also_image2 = ImageFlyweight.subdir_img2_png;
    assert(image2 is also_image2);

    // Its s possible to manually unload one or all instances, be careful to not access them afterwards!
    ImageFlyweight.unload(ImageFlyweight.ID.subdir_img2_png);
    ImageFlyweight.unloadAll();
    // It is safe to call unload more than once, so when `image2` and `also_image2`
    // are destructed, nothing will happen
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.img1_png));
    assert(!ImageFlyweight.isLoaded(ImageFlyweight.ID.subdir_img2_png));
}
```
