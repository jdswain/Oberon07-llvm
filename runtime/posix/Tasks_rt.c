/* Tasks_rt.c — cooperative stackful scheduler for Tasks.Mod (DDR-014, Opt 1).
 *
 * One OS thread, N green tasks, each with its own stack (ucontext). A task
 * runs until it Yields or blocks on I/O; control swaps back to the scheduler,
 * which drives poll() and resumes tasks whose fd became ready. Because
 * switches happen only at these explicit points, tasks never preempt each
 * other — shared state is safe between yields, so there are no locks and no
 * memory model (DDR-014 §2). This is the LLVM/POSIX scheduler; the 816/OS16
 * scheduler is a separate implementation (DDR-014 §2.1).
 *
 * Division of labour with Tasks.Mod: C owns the stacks, contexts, run queue
 * and poll set; Oberon owns the task objects and dispatch. The fat interface
 * pointer of a Task never crosses into C — the scheduler calls one Oberon
 * entry, Tasks.taskMain(id), which looks the object up and invokes its Run.
 */
#define _XOPEN_SOURCE 700
#include <poll.h>
#include <stdlib.h>
#include <ucontext.h>

/* ucontext is deprecated on macOS but still the simplest portable stackful
   switch; the alternative is per-arch asm. Silence the deprecation notice. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define MAX_TASKS 1024
#define STACK_SIZE (256 * 1024)

enum { T_FREE = 0, T_READY, T_RUNNING, T_BLOCKED, T_DONE };

typedef struct {
    ucontext_t ctx;
    char *stack;
    int state;
    int wait_fd;    /* fd this task is blocked on, -1 = none */
    int wait_want;  /* bit0 = readable, bit1 = writable */
} task_t;

static task_t g_tasks[MAX_TASKS];
static ucontext_t g_sched;      /* the scheduler's own context */
static int g_current = -1;      /* running task id, -1 = in scheduler */
static int g_cursor = 0;        /* round-robin start for fairness */

/* Oberon entry: runs taskList[id].Run(). Defined in Tasks.Mod. */
extern void Tasks__taskMain(int id);

static void trampoline(int id) {
    Tasks__taskMain(id);
    g_tasks[id].state = T_DONE;
    swapcontext(&g_tasks[id].ctx, &g_sched);   /* back to scheduler, forever */
}

/* --- surface: strong overrides of the weak Tasks.Mod stubs --- */

/* Allocate a task slot and prime its context. Returns id, or -1 if full.
   The caller (Tasks.SpawnTask) stores the Task object at this id before the
   scheduler ever runs it. */
int Tasks__spawnRaw(void) {
    int id = -1, i;
    for (i = 0; i < MAX_TASKS; i++) {
        if (g_tasks[i].state == T_FREE) { id = i; break; }
    }
    if (id < 0) return -1;
    g_tasks[id].stack = malloc(STACK_SIZE);
    if (g_tasks[id].stack == NULL) return -1;
    getcontext(&g_tasks[id].ctx);
    g_tasks[id].ctx.uc_stack.ss_sp = g_tasks[id].stack;
    g_tasks[id].ctx.uc_stack.ss_size = STACK_SIZE;
    g_tasks[id].ctx.uc_link = NULL;
    makecontext(&g_tasks[id].ctx, (void (*)(void))trampoline, 1, id);
    g_tasks[id].state = T_READY;
    g_tasks[id].wait_fd = -1;
    g_tasks[id].wait_want = 0;
    return id;
}

void Tasks__Yield(void) {
    int id = g_current;
    if (id < 0) return;                 /* not in a task: nothing to yield to */
    g_tasks[id].state = T_READY;
    swapcontext(&g_tasks[id].ctx, &g_sched);
}

/* The scheduler. Runs until every task has finished. */
void Tasks__Run(void) {
    static struct pollfd pf[MAX_TASKS];
    static int idx[MAX_TASKS];
    for (;;) {
        int i, nready = 0, np = 0;

        for (i = 0; i < MAX_TASKS; i++) {
            if (g_tasks[i].state == T_DONE) {
                free(g_tasks[i].stack);
                g_tasks[i].stack = NULL;
                g_tasks[i].state = T_FREE;
            }
        }
        for (i = 0; i < MAX_TASKS; i++) {
            if (g_tasks[i].state == T_READY) {
                nready++;
            } else if (g_tasks[i].state == T_BLOCKED) {
                pf[np].fd = g_tasks[i].wait_fd;
                pf[np].events = 0;
                if (g_tasks[i].wait_want & 1) pf[np].events |= POLLIN;
                if (g_tasks[i].wait_want & 2) pf[np].events |= POLLOUT;
                pf[np].revents = 0;
                idx[np] = i;
                np++;
            }
        }
        if (nready == 0 && np == 0) break;      /* all tasks finished */

        if (np > 0) {
            /* If something is already runnable, just harvest ready fds
               without waiting; otherwise block until one becomes ready. */
            int r = poll(pf, np, nready > 0 ? 0 : -1);
            if (r > 0) {
                int k;
                for (k = 0; k < np; k++) {
                    if (pf[k].revents != 0) {
                        int t = idx[k];
                        g_tasks[t].state = T_READY;
                        g_tasks[t].wait_fd = -1;
                        nready++;
                    }
                }
            }
        }
        if (nready == 0) continue;              /* re-poll the blocked set */

        {   /* pick the next ready task, round-robin from the cursor */
            int pick = -1, s;
            for (s = 0; s < MAX_TASKS; s++) {
                int t = (g_cursor + s) % MAX_TASKS;
                if (g_tasks[t].state == T_READY) { pick = t; break; }
            }
            if (pick < 0) continue;
            g_cursor = (pick + 1) % MAX_TASKS;
            g_current = pick;
            g_tasks[pick].state = T_RUNNING;
            swapcontext(&g_sched, &g_tasks[pick].ctx);
            g_current = -1;
        }
    }
}

/* --- I/O-wait hook (installed into runtime.c's oc_iowait) ---
   Park the current task until fd is ready; outside a task, block on poll. */
static int tasks_wait_fd(int fd, int want) {
    int id = g_current;
    if (id < 0) {
        struct pollfd p;
        p.fd = fd;
        p.events = 0;
        if (want & 1) p.events |= POLLIN;
        if (want & 2) p.events |= POLLOUT;
        p.revents = 0;
        return poll(&p, 1, -1);
    }
    g_tasks[id].wait_fd = fd;
    g_tasks[id].wait_want = want;
    g_tasks[id].state = T_BLOCKED;
    swapcontext(&g_tasks[id].ctx, &g_sched);
    return 1;                                    /* resumed => fd is ready */
}

__attribute__((constructor))
static void tasks_install(void) {
    extern int (*oc_iowait_hook)(int fd, int want);
    oc_iowait_hook = tasks_wait_fd;
}
