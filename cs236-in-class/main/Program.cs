namespace main;

internal static class Program
{
    private static void Main()
    {
        IDisplayable[] animals =
        {
            new Dog(), new Cat()
        };

        PrintDisplayNames(animals);
    }

    private static void PrintDisplayNames(IDisplayable[] displayables)
    {
        foreach (IDisplayable displayable in displayables)
        {
            Console.WriteLine("Display name: " + displayable.GetDisplayName());
        }
    }
}