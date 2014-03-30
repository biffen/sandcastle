#include <functional>
#include <initializer_list>
#include <iostream>
#include <string>

/**
 * A switch-like feature with a few improvements over the built-in:
 *
 * - Any type can be used as input.
 *
 * - Cases can, optionally, return a value that is then returned by the outer
 *   switch.  It doesn't have to be of the same type as the input, making it
 *   ideal for translation type tasks.
 *
 * - Cases can, optionally, be chosen on a custom predicate, i.e. they don't
 *   have to equal the input to be "chosen".
 *
 * - The input (the thing to "switch on") and the keys for the cases don't have
 *   to be of the same type.  (If they are not comparable with `==` a custom
 *   predicate is necessary.)
 *
 * - Since the case "bodies" are `std::function`s, they can be either written
 *   inline (as lambdas) or refer to other functions.
 *
 * Naturally, there are some drawbacks:
 *
 * - No fall-through.  Can be overcome by:
 *
 *     - Specifying a number of case bodies as the same external function.
 *
 *     - Making the case keys lists, and the predicate the existence of the
 *       input within the key.
 *
 * - Compilers are unlikely to be able to do as much optimisation as with
 *   ordinary switches.
 *
 * It allows for things like:
 *
 *     int x = switchlike<const std::string,
 *                        const std::string,
 *                        int>(
 *       string_variable,       // switch (string_variable)
 *       {
 *         {
 *           "foo",             // case "foo":
 *           [](){
 *             return 1;
 *           }
 *         }, {
 *           "bar",             // case "bar":
 *           [](){
 *             return 2;
 *           }
 *         }
 *       },
 *       [](){                  // default:
 *         return 0;
 *       }
 *     );
 *
 * The above will map an `std::string` to an `int`, where "foo" becomes 1, "bar"
 * becomes 2 and the default is 0.  (The default predicate (`==`) is used.)
 *
 * Note that the default bit is mandatory when returning something. (Which makes
 * a lot of sense if you think about it.)
 *
 * An other example:
 *
 *     switchlike<const int,
 *                const int,
 *                void>(
 *       int_variable,          // switch (int_variable)
 *       {
 *         // cases...
 *       },
 *       [](){},                // default:
 *       [](const int a,
 *          const int b) {
 *            return (a % b) == 0;
 *          }
 *     );
 *
 * The above switches not on the *equality* of the input and the cases, but
 * rather on the result of a mathematical operation on each combination.
 *
 * Other similar uses would be "loose" string matching, regular expression
 * matching, range checks, the existence of a value within a set, etc, etc.
 *
 * @tparam input_type The type of the input.
 *
 * @tparam case_type The type of the values that identify the cases.  Unless
 *                   `predicate` is supplied it needs to be comparable to
 *                   `input_type` like so:  `case_type == input_type`
 *
 * @tparam return_type The return type of this function and of each case.  Can
 *                     be `void` to not return anything.
 *
 * @param input The value for which to switch.
 *
 * @param cases The cases, mapping keys (`input_type`s) to their functions.
 *
 * @param default_func The default case function (like `default` in regular
 *                     switches).  Optional *if* `return_type` is `void`, in
 *                     which case it will do nothing.
 *
 * @param predicate A function, that takes an `input_type`; `input`, and a
 *                  `case_type`; the case's key, and returns a `bool`.  If it
 *                  returns `true` for a case, then that case's function will be
 *                  called and the switch will return.  Does not have to be a
 *                  comparison per se.  Optional, the default will compare the
 *                  key to `input` using `==`.
 *
 * @return Whatever the "chosen" case returns, or what `default_func` returns if
 *         no case was chosen.  Nothing if `return_type` is `void`.
 */
template<typename input_type,
         typename case_type,
         typename return_type>
return_type switchlike(
  input_type                                                       input,
  std::initializer_list<std::pair<case_type,
                                  std::function<return_type()> > > cases,
  std::function<return_type()>                                     default_func
    = [] (){},
  std::function<bool(input_type,
                     case_type)>                                   predicate
    = [] (input_type a,
          case_type b){
      return b == a;
    }
) {
  for (std::pair<input_type, std::function<return_type()> > caze : cases) {
    if (predicate(input, caze.first) ) {
      return (caze.second )();
    }
  }

  return default_func();
}

#include <BugEye.h>

NAMED_TEST(switchlike, 3) {

  // string
  std::string x = "foo";
  switchlike<const std::string,
             const std::string,
             void>(
    x, {
      {
        "bar",
        [&] (){
          fail("Wrong case for foo");
        }
      },
      {
        "foo",
        [&] (){
          pass("Right case for foo");
        }
      }
    }
  );

  // int
  switchlike<const int,
             const int,
             void>(
    1,
    {
      {
        5,
        [&] (){
          fail("Wrong case for 1");
        }
      }
    },
    [&] (){
      pass("Right case for 1");
    },
    [] (const int a,
        const int b){
      return a % b == 0;
    }
  );

  // Return value (with default)
  int y = switchlike<const int,
                     const int,
                     int>(
    1,
    {
      {
        1,
        [] (){
          return 5;
        }
      }
    },
    [] (){
      return -1;
    }
          );
  is(y, 5, "y is 5");

}
