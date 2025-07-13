namespace main;

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