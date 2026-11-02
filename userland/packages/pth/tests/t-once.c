/* t-once.c -- pthread_once under contention, recursion and cancellation.
 * MIT, see LICENSE.amix in the package. */
#include <pthread.h>
#include <errno.h>
#include <stdio.h>

static int bad;
static void res(int ok, const char *what)
{
    printf("RES %s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok)
        bad++;
}

/* 1. four callers, an initialiser that yields: it runs once, and every
 *    caller returns after it has finished */
static pthread_once_t o1 = PTHREAD_ONCE_INIT;
static int runs1, done1, early1;
static void init1(void)
{
    int i;
    runs1++;
    for (i = 0; i < 50; i++)
        pthread_yield_np();
    done1 = 1;
}
static void *caller1(void *arg)
{
    pthread_once(&o1, init1);
    if (!done1)
        early1++;
    return NULL;
}

/* 2. an initialiser calling pthread_once on its own control: EDEADLK */
static pthread_once_t o2 = PTHREAD_ONCE_INIT;
static int rc2 = -1;
static void init2(void)
{
    rc2 = pthread_once(&o2, init2);
}

/* 3. a cancelled initialiser: its control is reset, a waiter then runs
 *    the initialiser itself, and later callers do not */
static pthread_once_t o3 = PTHREAD_ONCE_INIT;
static int in3, runs3b;
static void init3(void)
{
    in3 = 1;
    for (;;) {
        pthread_testcancel();
        pthread_yield_np();
    }
}
static void init3b(void)
{
    runs3b++;
}
static void *runner3(void *arg)
{
    pthread_once(&o3, init3);
    return NULL;
}
static void *waiter3(void *arg)
{
    pthread_once(&o3, init3b);
    return NULL;
}

int main(void)
{
    pthread_t t[4], r, w;
    int i;
    char buf[100];

    for (i = 0; i < 4; i++)
        pthread_create(&t[i], NULL, caller1, NULL);
    for (i = 0; i < 4; i++)
        pthread_join(t[i], NULL);
    sprintf(buf, "contended once: %d run(s), %d early return(s)", runs1, early1);
    res(runs1 == 1 && early1 == 0, buf);

    pthread_once(&o2, init2);
    sprintf(buf, "once from its own initialiser: %d (EDEADLK %d)", rc2, EDEADLK);
    res(rc2 == EDEADLK, buf);

    pthread_create(&r, NULL, runner3, NULL);
    for (i = 0; i < 10 && !in3; i++)
        pthread_yield_np();
    pthread_create(&w, NULL, waiter3, NULL);
    for (i = 0; i < 10; i++)
        pthread_yield_np();
    pthread_cancel(r);
    pthread_join(r, NULL);
    pthread_join(w, NULL);
    pthread_once(&o3, init3b);
    sprintf(buf, "cancelled initialiser: the waiter ran it, %d run(s), state %d", runs3b, o3);
    res(in3 && runs3b == 1 && o3 == 1, buf);

    printf("RES %s t-once\n", bad ? "FAIL" : "ok  ");
    return bad != 0;
}
