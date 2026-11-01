/* t-errno.c -- each Pth thread keeps its own errno across switches, and a
 * new thread starts with errno 0.  MIT, see LICENSE.amix in the package. */
#include <pthread.h>
#include <errno.h>
#include <stdio.h>

static int bad;

static void *worker(void *arg)
{
    int mine = (int) (long) arg, i;

    if (errno != 0) {
        printf("RES FAIL thread %d started with errno %d\n", mine, errno);
        bad++;
    }
    for (i = 0; i < 1000; i++) {
        errno = mine;
        pthread_yield_np();
        if (errno != mine) {
            printf("RES FAIL thread %d: errno %d after a switch\n", mine, errno);
            bad++;
            break;
        }
    }
    return NULL;
}

int main(void)
{
    pthread_t t[4];
    int i;

    errno = 77;
    for (i = 0; i < 4; i++)
        pthread_create(&t[i], NULL, worker, (void *) (long) (100 + i));
    for (i = 0; i < 4; i++)
        pthread_join(t[i], NULL);
    printf("RES %s t-errno: 4 threads x 1000 switches\n", bad ? "FAIL" : "ok  ");
    return bad != 0;
}
