namespace main;

public class Cat : Animal, IDisplayable
{
    public override string MakeSound()
    {
        return "Meow!";
    }

    public string GetDisplayName()
    {
        return "Cat";
    }
}