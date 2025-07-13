namespace main;

internal static class Program
{
    private static void Main()
    {
        Animal dog = new Dog();
        Animal cat = new Cat();
        
        Console.WriteLine("Dog makes: " + dog.MakeSound());
        Console.WriteLine("Cat makes: " + cat.MakeSound());
    }
}

public abstract class Animal
{
    public abstract string MakeSound();
}

public class Dog : Animal
{
    public override string MakeSound()
    {
        return "Woof!";
    }
}

public class Cat : Animal
{
    public override string MakeSound()
    {
        return "Meow!";
    }
}