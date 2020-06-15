module mocked.mocker;

import mocked.builder;
import mocked.error;
import mocked.meta;
import mocked.option;
import std.conv;
import std.format : format;
import std.traits;

private enum string overloadingCode = q{
    %2$s Overload.Return %1$s(Overload.ParameterTypes arguments)
    {
        auto overloads = __traits(getMember, builder, "%1$s").overloads[i];

        if (overloads.empty)
        {
            throw unexpectedCallError!(typeof(super), Overload.ParameterTypes)("%1$s", arguments);
        }
        if (!overloads.front.ignoreArgs_
                && !overloads.front.compareArguments!options(arguments))
        {
            __traits(getMember, builder, "%1$s").overloads[i].clear();

            throw unexpectedArgumentError!(typeof(super),
                    Overload.ParameterTypes, Overload.Arguments)(
                    "%1$s", arguments, overloads.front.arguments);
        }

        static if (is(Overload.Return == void))
        {
            if (overloads.front.action_ !is null)
            {
                overloads.front.action_(arguments);
            }
        }
        else
        {
            Overload.Return ret = void;

            if (overloads.front.action_ !is null)
            {
                ret = overloads.front.action_(arguments);
            }
            else
            {
                ret = overloads.front.return_;
            }
        }

        static if (!is(T == interface) && is(Overload.Return == void))
        {
            if (overloads.front.passThrough_)
            {
                __traits(getMember, super, "%1$s")(arguments);
            }
        }
        else static if (!is(T == interface))
        {
            if (overloads.front.passThrough_)
            {
                ret = __traits(getMember, super, "%1$s")(arguments);
            }
        }

        if (__traits(getMember, builder, "%1$s").overloads[i].front.repeat_ > 1)
        {
            --__traits(getMember, builder, "%1$s").overloads[i].front.repeat_;
        }
        else if (__traits(getMember, builder, "%1$s").overloads[i].front.repeat_ == 1)
        {
            __traits(getMember, builder, "%1$s").overloads[i].popFront;
        }

        static if (!canFind!("nothrow", Overload.qualifiers))
        {
            if (overloads.front.exception !is null)
            {
                throw overloads.front.exception;
            }
        }
        static if (!is(Overload.Return == void))
        {
            return ret;
        }
    }
};

/**
 * Mocker instance with default options.
 *
 * See_Also: $(D_PSYMBOL Factory), $(D_PSYMBOL configure).
 */
alias Mocker = Factory!(Options!());

/**
 * Constructs a mocker with options passed as $(D_PARAM Args).
 *
 * Params:
 *     Args = Mocker options.
 *
 * See_Also: $(D_PSYMBOL Factory), $(D_PSYMBOL Mocker).
 */
auto configure(Args...)()
{
    return Factory!(Options!Args)();
}

/**
 * A class through which one creates mock objects and manages expectations
 * about calls to their methods.
 *
 * Params:
 *     Options = Mocker $(D_PSYMBOL Options).
 *
 * See_Also: $(D_PSYMBOL Mocker), $(D_PSYMBOL CustomMocker).
 */
struct Factory(Options)
{
    Verifiable[] repositories;
    private enum Options options = Options();

    /**
     * Mocks the type $(D_PARAM T).
     *
     * Params:
     *     T = The type to mock.
     *     Args = Constructor parameter types.
     *     args = Constructor arguments.
     *
     * Returns: A mock builder.
     */
    auto mock(T, Args...)(Args args)
    {
        Repository!T builder;

        class Mock : T
        {
            static if (__traits(hasMember, T, "__ctor") && Args.length > 0)
            {
                this()
                {
                    super(args);
                }
            }
            else static if (__traits(hasMember, T, "__ctor"))
            {
                this()
                {
                    super(Parameters!(T.__ctor).init);
                }
            }

            static foreach (expectation; builder.ExpectationTuple)
            {
                static foreach (i, Overload; expectation.Overloads)
                {
                    static if (is(T == class))
                    {
                        mixin(format!overloadingCode(expectation.name,
                                unwords!("override", Overload.qualifiers)));
                    }
                    else
                    {
                        mixin(format!overloadingCode(expectation.name,
                                unwords!(Overload.qualifiers)));
                    }
                }
            }
        }

        auto mock = new Mock();
        auto repository = new Mocked!T(mock, builder);

        this.repositories ~= repository;
        return repository;
    }

    /**
     * Verifies that certain expectation requirements were satisfied.
     *
     * Throws: $(D_PSYMBOL ExpectationViolationException) if those issues occur.
     */
    void verify()
    {
        foreach (repository; this.repositories)
        {
            repository.verify;
        }
    }

    ~this()
    {
        verify;
    }
}
