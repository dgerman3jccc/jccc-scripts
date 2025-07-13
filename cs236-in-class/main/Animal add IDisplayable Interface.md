In-Class Assignment: Unrelated Interfaces with Animal Classes
=============================================================

Objective
---------

Demonstrate the use of interfaces to introduce polymorphism among unrelated classes. You will create an `IDisplayable` interface and apply it to the existing animal classes.

Starter Code
------------

You should already have the `Animal`, `Dog`, `Cat` classes from previous assignments.

Instructions
------------

1.  Create IDisplayable Interface: Define an interface named `IDisplayable` with a method `GetDisplayName` that returns a string.

2.  Modify Animal Classes: Update the `Dog`, `Cat`, and other animal classes to implement the `IDisplayable` interface. Provide an implementation for the `GetDisplayName` method, returning a string that represents the animal's name.

3.  Create a Method: Define a method named `PrintDisplayNames` in the `Program` class that takes an array of `IDisplayable` objects as a parameter and prints the display name for each object:

4.  Modify Main Method: Update the main method to create an array of `IDisplayable` objects containing instances of `Dog` and `Cat`, then call `PrintDisplayNames` with this array.

5.  Compile and Run: Compile and run the code. Verify that the program prints the display names correctly.

* * * * *

In this assignment, the `IDisplayable` interface could be applied to many different types of classes, not just animals, demonstrating how interfaces can provide a common contract across unrelated classes.