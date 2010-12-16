/*
    Title:      Task farm for Multi-Threaded Garbage Collector

    Copyright (c) 2010 David C. J. Matthews

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.
    
    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.
    
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

*/

#ifndef GCTASKFARM_H_INCLUDED
#define GCTASKFARM_H_INCLUDED

#include "locking.h"

// Function for action.  The usual C++ approach would be to use an
// object pointer but that requires lots of small objects to be created
// and deleted.
typedef void (*gctask)(void*, void*);

typedef struct {
    gctask  task;
    void    *arg1;
    void    *arg2;
} queue_entry;

class GCTaskFarm {
public:
    GCTaskFarm();
    ~GCTaskFarm();

    bool Initialise(unsigned threadCount, unsigned queueSize);

    bool AddWork(gctask task, void *arg1, void *arg2);
    void AddWorkOrRunNow(gctask task, void *arg1, void *arg2);
    void WaitForCompletion(void);
    void Terminate(void);

private:
    void DebugOutput(const char *debug);

    // The semaphore is zero if there is no work or some value up to
    // the number of threads if there is work.
    PSemaphore waitForWork;
    // The lock protects the queue and the item count.
    PLock workLock;
    // The condition variable is signalled when the queue is empty.
    // This can only be waited for by a single thread because it's not a proper
    // implementation of a condition variable in Windows.
    PCondVar waitForCompletion;
    unsigned queueSize, queuedItems;
    queue_entry *workQueue; // Array of unit->unit functions.
    bool terminate; // Set to true to kill all workers.
    unsigned threadCount; // Count of workers.
    unsigned activeThreadCount; // Count of workers doing work.

    void ThreadFunction(void);

#ifdef HAVE_PTHREAD
    static void *WorkerThreadFunction(void *parameter);
#else
    static DWORD WINAPI WorkerThreadFunction(void *parameter);
#endif
};

#endif
