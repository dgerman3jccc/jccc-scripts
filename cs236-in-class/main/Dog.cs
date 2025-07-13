namespace main;

public class Dog : Animal, IDisplayable
{
    public override string MakeSound()
    {
        return "Woof!";
    }

    public string GetDisplayName()
    {
        return "Dog";
    }
}