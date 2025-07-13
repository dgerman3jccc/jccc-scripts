namespace main;

internal static class Program
{
    private static void Main()
    {
        Animal[] animals =
        {
            new Dog(), new Cat()
        };

        PrintAnimalSounds(animals);
    }

    private static void PrintAnimalSounds(Animal[] animals)
    {
        foreach (Animal animal in animals)
        {
            Console.WriteLine("This animal makes: " + animal.MakeSound());
        }
    }
}