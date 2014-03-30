#include <BugEye.h>

int main(int    /*argc*/,
         char** /*argv*/) {
  BUGEYE_SET(verbosity, 2);
  BUGEYE_RUN;
}
