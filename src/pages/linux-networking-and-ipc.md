---
layout: ../layouts/GistLayout.astro
tags: [linux, networking, svelte, guide]
---

# Linux Networking & Inter-Process Communication

## Table of Contents

### Part I: Linux Fundamentals

1. [File Descriptors & the "Everything is a File" Model](#1-file-descriptors--the-everything-is-a-file-model)
2. [Processes: fork, exec, and the Process Tree](#2-processes-fork-exec-and-the-process-tree)
3. [FD Manipulation: dup, dup2](#3-fd-manipulation-dup-dup2)
4. [IPC Mechanisms](#4-ipc-mechanisms)
5. [The Socket API](#5-the-socket-api)
6. [The TCP/IP Network Stack](#6-the-tcpip-network-stack)
7. [Socket Addressing](#7-socket-addressing)
8. [Socket Options](#8-socket-options)
9. [I/O Multiplexing & Async I/O](#9-io-multiplexing--async-io)
10. [Debugging & Observability](#10-debugging--observability)

### Part II: Case Study

11. [Svelte SSR + Go Backend Architecture](#11-case-study-svelte-ssr--go-backend-architecture)

---

# Part I: Linux Fundamentals

---

# 1. File Descriptors & the "Everything is a File" Model

## What is a File Descriptor?

A file descriptor is simply a **non-negative integer** that a process uses to refer to an open I/O resource. It's a handle — an opaque reference that the kernel understands. The process doesn't interact with the resource directly; it hands the fd to syscalls like `read()`, `write()`, `close()`, and the kernel does the actual work. Think of it like a coat check ticket: you don't carry the coat around, you carry a number that the cloakroom (kernel) uses to find your coat.

In Linux, every I/O resource — files, pipes, sockets, devices — gets a file descriptor when opened. The kernel maintains a per-process fd table mapping these integers to internal kernel objects:

```
Process fd table:
  fd 0 → stdin (pipe)
  fd 1 → stdout (pipe)
  fd 2 → stderr (pipe)
  fd 3 → socket (TCP, listening on :8080)
  fd 4 → socket (TCP, connected to client A)
  fd 5 → socket (Unix domain, connected to another process)
  fd 6 → file (/var/log/app.log)
  fd 7 → device (/dev/urandom)
```

Every I/O operation boils down to `read(fd, ...)` and `write(fd, ...)` on these descriptors. The kernel implements different behavior depending on what the fd points to — but the interface is uniform.

## What is a Device?

A device is a **kernel object with a driver** that implements the standard file operations interface. It doesn't have to be physical hardware — it's anything the kernel exposes through the file abstraction.

At the kernel level, a driver registers a set of functions:

```c
struct file_operations {
    int (*open)(...);
    ssize_t (*read)(...);
    ssize_t (*write)(...);
    long (*ioctl)(...);      // device-specific commands beyond read/write
    int (*mmap)(...);
    int (*release)(...);     // close
    __poll_t (*poll)(...);   // for epoll/select readiness
};
```

When you `open("/dev/something")`, the kernel looks up which driver owns that file, and routes all subsequent `read()`/`write()`/`ioctl()` calls to that driver's functions. **A "device" is really just: a set of functions the kernel calls when you interact with a specific file.** Whether there's actual hardware behind those functions is an implementation detail.

For example, `/dev/null`'s write function is essentially `return count;` — it says "yep, wrote everything" and discards the data. No hardware involved.

### Device categories

**Physical hardware** — actual chips/peripherals, accessed via drivers:
```
/dev/sda          → SCSI/SATA disk (block device — fixed-size blocks)
/dev/nvme0n1      → NVMe drive (block device)
/dev/nvme0n1p1    → first partition on it
/dev/input/event0 → USB keyboard/mouse (character device — byte stream)
/dev/dri/card0    → GPU
/dev/snd/pcm*     → sound card
/dev/ttyS0        → serial port
```

**Virtual/pseudo devices** — no hardware, kernel implements the behavior:
```
/dev/null         → discards writes, returns EOF on read
/dev/zero         → infinite zeros on read
/dev/full         → always returns "disk full" on write (for testing)
/dev/random       → cryptographic random bytes (may block for entropy)
/dev/urandom      → random bytes (never blocks, preferred for most uses)
/dev/loop0        → makes a regular file behave like a block device
```

**Kernel subsystems exposed as devices:**
```
/dev/kvm          → virtualization interface
/dev/fuse         → userspace filesystem interface
/dev/net/tun      → virtual network interface (VPNs use this)
/dev/pts/0        → pseudo-terminal (what your terminal emulator uses)
```

### How device files connect to drivers (major/minor numbers)

```bash
ls -l /dev/sda
# brw-rw---- 1 root disk 8, 0 ...
#                         ^  ^
#                     major  minor
# major 8 = SCSI disk driver, minor 0 = first disk
```

When you `open("/dev/sda")`, the kernel looks up major number 8 in its driver table, finds the SCSI driver, and routes all calls to that driver.

### Why the network card has no /dev entry

Network I/O is packet-oriented with addressing (IP/port) and multiplexing — fundamentally different from a byte stream. So networking got its own API (sockets, covered in sections 5-6) rather than being shoehorned into read/write on a device file.

## Virtual Filesystems — Kernel State as Files

Beyond `/dev`, Linux exposes process information and hardware topology as virtual filesystems:

### `/proc` — processes and kernel parameters

```
/proc/1234/fd/      → all open fds for PID 1234 (symlinks to actual resources)
/proc/1234/maps     → memory map of the process
/proc/1234/status   → process state (running, sleeping, zombie, etc.)
/proc/self/         → always refers to the calling process
/proc/sys/          → kernel tunable parameters (sysctl values — see section 8)
```

### `/sys` — hardware topology

```
/sys/class/net/eth0/speed       → link speed in Mbps (e.g., "1000")
/sys/class/net/eth0/address     → MAC address
/sys/block/sda/size             → disk size in sectors
/sys/devices/system/cpu/cpu0/   → CPU 0 info and controls
```

### `/dev/fd/` — file descriptors as file paths

```
/dev/fd/0       → this process's stdin
/dev/fd/1       → this process's stdout
/dev/fd/2       → this process's stderr
```

Lets you use an fd where a file path is expected: `cat /dev/fd/3` reads from fd 3.

### `/dev/shm` — shared memory as files

tmpfs mount for POSIX shared memory. `shm_open()` creates files here. Covered in section 4.5.

## Why "Everything is a File" Matters

Since devices, processes, and kernel state are all fds, every tool in this document works with them:
- `epoll` can monitor `/dev/input/event0` for keyboard events
- `dup2` can redirect stdout to `/dev/null` (silence a program)
- Pipes connect programs to devices: `cat /dev/urandom | head -c 32 | base64`
- `mmap` works on block devices (memory-mapped disk I/O)

The uniform fd interface means all the IPC and multiplexing machinery works for devices too.

## How the Kernel Knows When an FD is "Ready"

The fd table is per-process, but the **kernel object** behind it (a socket, pipe, device) is independent — multiple processes can share the same one. The kernel object doesn't "belong" to any process.

The mechanism is **wait queues** — it's event-driven, not polling:

```
1. Process says "I want to read from this socket"
   (calls read(), or epoll_wait(), or poll())
        │
        ▼
2. Kernel registers the process on the socket's WAIT QUEUE
   Process goes to sleep (removed from CPU)
        │
        ▼
   [Time passes... socket is idle... process is sleeping]
        │
        ▼
3. Data arrives (hardware interrupt from NIC)
   Kernel places data in socket's recv buffer
        │
        ▼
4. Kernel walks the socket's wait queue:
   "Who wanted to know about this socket?"
   Finds the sleeping process → wakes it up
        │
        ▼
5. Scheduler gives the process CPU time
   read() returns with the data
```

**Key point:** The kernel never searches "which process owns this fd?" — processes announce their interest *upfront* by registering on the wait queue. When data arrives, the kernel just walks the list and wakes everyone who registered.

```
Socket (kernel object, lives independently in the kernel)
├── recv buffer: [incoming data...]
├── send buffer: [outgoing data...]
└── wait queue:
      ├── Process A: "wake me when readable"
      ├── Process B: "wake me when readable"
      └── epoll instance: "add me to your ready-list"
```

Multiple processes can wait on the same object. The fd number is just how *each process* refers to the object — the kernel object doesn't know or care about fd numbers.

**What "ready" means depends on the fd type:**

| fd type | "Readable" when... | "Writable" when... |
|---------|--------------------|--------------------|
| TCP socket | recv buffer has data, or FIN received, or new conn in accept queue | send buffer has space |
| UDS | recv buffer has data | send buffer has space |
| Pipe | pipe buffer has data | pipe buffer has space |
| Regular file | **Always** (this is why epoll can't do async file I/O) |
| eventfd | counter > 0 | always |

Regular files are always "ready" because blocking happens *inside* the `read()` syscall (waiting for disk), not at the fd level. This is the limitation io_uring solves (section 9).

---

# 2. Processes: fork, exec, and the Process Tree

## fork() and Copy-on-Write (COW)

`fork()` is the **only way** to create a new process on Linux. It creates a child process that is a copy of the parent. But the kernel doesn't actually duplicate memory — it uses a trick called **Copy-on-Write**:

```
Before fork:
  Parent: [page1] [page2] [page3] ... [pageN]

After fork (instant, near-zero cost):
  Parent: ──┐
            ├──► [page1] [page2] [page3] ... [pageN]  (shared, marked read-only)
  Child:  ──┘

When parent writes to page2 (COW triggers):
  Parent: ──────► [page1] [page2'] [page3] ... [pageN]   ← new copy of page2
  Child:  ──────► [page1] [page2 ] [page3] ... [pageN]   ← still has original
```

**How it works:**
1. `fork()` marks all memory pages as shared + read-only
2. Both processes continue running, reading from the same physical pages
3. When either process **writes** to a page, the CPU triggers a page fault
4. Kernel intercepts the fault, copies just that one page, gives the writer its own copy
5. Only modified pages ever get duplicated

**The Redis example — why COW is powerful:**

Redis keeps its entire dataset in memory. When it needs to save to disk:

```
Redis (parent): serving requests, modifying data
        │
        └── fork()
              │
              ├── Parent: continues serving reads & writes
              │     (writes trigger COW — only touched pages get copied)
              │
              └── Child: has a FROZEN point-in-time snapshot
                    Iterates through memory, writes to disk (RDB file)
                    Exits when done
```

The child gets a consistent snapshot for free — no locks, no pausing the server. The memory cost is only the pages the parent modifies during the save (typically a small fraction). If the parent is write-heavy during this period, memory can temporarily spike (worst case: 2× usage).

**fork() and file descriptors:**

The child inherits a *copy* of the parent's fd table. Both processes now have fds pointing to the **same kernel objects** (same sockets, same pipes, same files). This is how pipes between parent and child work — they share the underlying kernel pipe object via their inherited fds.

```
After fork:
  Parent fd table:              Child fd table:
    fd 3 → socket A              fd 3 → socket A  (same kernel object!)
    fd 4 → pipe (write end)      fd 4 → pipe (write end)
    fd 5 → file                  fd 5 → file
```

**Other uses of fork + COW:**
- Redis (persistence snapshots, as shown above)
- PostgreSQL forks per client connection
- Chrome forks renderer processes for isolation
- Nginx forks worker processes (fork without exec — workers run the same code)

## fork() + exec() — How Every Program on Linux Starts

Linux has no "spawn a new program" syscall. The only way to run a different program is `exec()`, which replaces the current process's memory with a new program. Combined with fork, this gives the universal two-step pattern:

1. **`fork()`** — clone the current process
2. **`exec()`** — replace the clone's memory with a new program

```
bash (PID 100)
  │
  ├── fork() ──► bash clone (PID 101)   ← identical copy of bash
  │                  │
  │                  └── exec("ls") ──► ls (PID 101)   ← memory replaced with ls binary
  │                                       │
  │                                       └── exits
  │
  ├── waitpid(101) ← bash was waiting here
  └── prints prompt again
```

This isn't just for terminals — it's **everything**:

| What happens | Who calls fork+exec |
|---|---|
| Type `ls` in terminal | bash forks+execs /bin/ls |
| Click an app in GUI | Desktop environment forks+execs the app |
| systemd starts a service | systemd forks+execs the service binary |
| Docker runs a container | containerd forks+execs the entrypoint |
| cron runs a job | crond forks+execs the command |
| SSH login | sshd forks+execs your shell |

**The only exception:** PID 1 (init/systemd) is created directly by the kernel during boot. After that, every process on the system is a descendant created via `fork()`.

### Why two steps instead of one "spawn" call?

The gap between fork and exec is where setup happens:

```c
pid = fork();

if (pid == 0) {
    // Child — still running parent's code, can set things up:
    dup2(file_fd, 1);       // redirect stdout (for > output.txt)
    dup2(pipe_fd, 0);       // redirect stdin (for pipes)
    close(unwanted_fds);    // cleanup
    chdir("/some/path");    // change working directory
    setenv("FOO", "bar");  // set environment variables
    setuid(1000);           // drop privileges

    // NOW replace with the new program:
    exec("/bin/ls", "ls", "-la", NULL);
    // if exec succeeds, this line never runs — ls is running now
}

// Parent waits:
waitpid(pid, &status, 0);
```

A single "spawn" syscall would need parameters for every possible setup option — impossible to design generically. The two-step pattern lets you use any combination of syscalls in between.

### What exec() keeps vs replaces

| Kept (inherited) | Replaced (wiped) |
|---|---|
| PID | All memory (code, heap, stack) |
| fd table (open files, sockets) | Program instructions |
| Working directory | Global variables |
| Environment variables | |
| uid/gid | |

This is why dup2 before exec works — the new program inherits the modified fd table.

### "Isn't copying the whole process wasteful just to throw it away with exec?"

No — because of COW. `fork()` doesn't copy memory, just marks page table entries as shared. Then `exec()` releases all those pages immediately and loads the new program. Actual cost: microseconds.

## The Process Tree

Every Linux system is a tree rooted at PID 1:

```
PID 1: systemd (the one exception — created by kernel at boot)
  ├── sshd
  │     └── bash ← fork+exec by sshd on login
  │           ├── ls ← fork+exec by bash
  │           └── vim ← fork+exec by bash
  ├── nginx (master)
  │     ├── nginx (worker) ← fork only, no exec (same program)
  │     └── nginx (worker)
  ├── postgres
  │     ├── postgres (bg writer) ← fork only
  │     └── postgres (client handler) ← fork only
  └── docker
        └── containerd
              └── your-app ← fork+exec
```

```bash
# See it yourself:
pstree -p    # visual tree with PIDs
ps -ef --forest
```

---

# 3. FD Manipulation: dup, dup2

`dup()` creates a **second fd number** that points to the **same kernel object** as an existing fd. Both fds are fully interchangeable — reading/writing on either one affects the same underlying resource.

```c
int new_fd = dup(old_fd);      // kernel picks the lowest available fd number
int new_fd = dup2(old_fd, 7);  // forces the new fd to be exactly 7
```

```
Before dup:
  fd 3 → [Socket object]

After: new_fd = dup(3)  →  returns fd 4
  fd 3 ──┐
         ├──► [Socket object]  (same object, shared position, shared state)
  fd 4 ──┘
```

It's like having two coat-check tickets for the same coat. Either ticket lets you retrieve it.

**The critical detail:** `dup()` works *within a single process* (unlike `fork()` which creates two processes sharing objects). The duplicated fd shares everything — file offset, status flags, locks.

## How Shells Use dup2() for I/O Redirection

When you type `ls > output.txt`, the shell does:

```c
int fd = open("output.txt", O_WRONLY | O_CREAT);  // e.g., gets fd 3
fork();                                             // child inherits fds
// In the child:
dup2(fd, 1);    // makes fd 1 (stdout) point to output.txt
close(fd);      // fd 3 no longer needed
exec("ls");     // ls writes to fd 1, which is now the file
```

`ls` has no idea its stdout is a file — it just writes to fd 1 as always. The shell swapped what fd 1 points to before `ls` started.

## How Pipes Between Commands Work

When you type `ls | grep foo`:

```c
int pipefd[2];
pipe(pipefd);           // pipefd[0] = read end, pipefd[1] = write end

if (fork() == 0) {      // Child 1: runs "ls"
    dup2(pipefd[1], 1); // stdout → pipe write end
    close(pipefd[0]);
    close(pipefd[1]);
    exec("ls");
}

if (fork() == 0) {      // Child 2: runs "grep foo"
    dup2(pipefd[0], 0); // stdin → pipe read end
    close(pipefd[0]);
    close(pipefd[1]);
    exec("grep", "foo");
}
```

`ls` writes to stdout (fd 1) → goes into pipe → `grep` reads from stdin (fd 0). Neither program knows about the pipe — they just use the standard fd numbers.

## Who Uses dup/dup2?

| User | What they do |
|------|-------------|
| **Shells** (bash, zsh) | I/O redirection (`>`, `<`, `\|`) — swap stdin/stdout/stderr before exec |
| **Daemons** | Redirect stdin/stdout/stderr to /dev/null or log files after daemonizing |
| **inetd/systemd** | Accept a network connection, dup2 the socket fd onto fd 0 and 1, exec the handler — handler just reads stdin/writes stdout |
| **Logging** | dup stderr to a log file so all error output goes to both |
| **nginx** | During graceful restart: pass the listening socket fd to the new process |

## Three Ways to Share a Kernel Object

| Mechanism | Scope | How |
|-----------|-------|-----|
| `dup()` | Same process, new fd number | Copies fd table entry within one process |
| `fork()` | Parent + child, same fd numbers | Child inherits entire fd table |
| `sendmsg(SCM_RIGHTS)` | Unrelated processes | Passes fd over a Unix domain socket (section 4.3) |

---

# 4. IPC Mechanisms

All the ways two processes on the same machine can exchange data. Now that we understand fds, fork, and dup — these build directly on those primitives.

## 4.1 STDIO (Anonymous Pipes)

**How it works:** Parent spawns a child process. The kernel creates pipe buffers (typically 64KB) connecting parent's write end to child's stdin, and child's stdout to parent's read end. Data never leaves kernel memory.

**Syscalls:** `pipe()`, `fork()`, `dup2()`, `read()`, `write()`

```
Parent process                    Child process
  write(stdin_fd) ──► [kernel pipe buffer] ──► read(fd 0)
  read(stdout_fd) ◄── [kernel pipe buffer] ◄── write(fd 1)
```

As shown in section 3, the shell uses exactly this — `pipe()` + `fork()` + `dup2()` + `exec()`.

**Characteristics:**
- One-to-one, unidirectional per pipe
- No message framing — raw byte stream, you must define your own protocol (newline-delimited JSON, length-prefix, etc.)
- No concurrency — single pipe is serial unless you add request ID multiplexing
- No addressing — only works between parent and child (or inherited fds)
- Fastest raw throughput for single-stream communication
- Buffer size: 64KB default (16 pages × 4KB), max typically 1MB

**Good for:** Simple parent-child communication, one-at-a-time request/response.

## 4.2 Named Pipes (FIFOs)

**How it works:** Like anonymous pipes but with a filesystem path. Any process can open the FIFO by name. Created with `mkfifo`.

```
Process A ──write──► /tmp/myfifo ──read──► Process B
```

**Characteristics:**
- Unidirectional (need two FIFOs for bidirectional)
- Any process can connect (not limited to parent-child)
- Same byte-stream semantics as anonymous pipes (no message framing)
- Simpler than Unix domain sockets but fewer features (no concurrent connections)

**Good for:** Simple one-way data flow between unrelated processes.

## 4.3 Unix Domain Sockets (UDS)

**How it works:** A socket that uses a **filesystem path** instead of IP:port for addressing. Uses the same socket API as TCP (bind, listen, accept, connect) but the kernel short-circuits the network stack entirely — no IP headers, checksums, routing, or congestion control. Data goes directly from one socket buffer to another within kernel memory.

**Syscalls:** `socket(AF_UNIX, ...)`, `bind()`, `listen()`, `accept()`, `connect()`

```
Process A (client)                         Process B (server)
  connect("/tmp/app.sock") ────────────► listen("/tmp/app.sock")
  socket_fd ◄──── kernel buffer ────────► socket_fd
```

**Characteristics:**
- Supports multiple concurrent connections (each `accept()` returns a new fd pair)
- Three modes: stream (`SOCK_STREAM`), datagram (`SOCK_DGRAM`), sequenced packets (`SOCK_SEQPACKET`)
- Permission controlled via filesystem mode bits on the socket path
- Any local process can connect (not limited to parent-child)
- HTTP works natively over it — standard framing, no custom protocol needed
- No TCP overhead: no handshake delay, no checksums, no TIME_WAIT, no Nagle buffering

**UDS-exclusive feature — File Descriptor Passing:**

Using `sendmsg()` with `SCM_RIGHTS` (the third method from section 3's comparison table):

```c
// Process A has fd pointing to an open file/socket
sendmsg(uds_fd, &msg_with_fd, 0);  // sends the fd to Process B

// Process B receives a NEW fd number pointing to the same kernel object
recvmsg(uds_fd, &msg, 0);          // gets a usable fd
```

The kernel duplicates the fd table entry in the receiving process. This is how container runtimes, systemd socket activation, and some IPC frameworks pass connections between processes.

**Good for:** Any local process-to-process communication that needs concurrency, bidirectionality, or HTTP semantics.

## 4.4 TCP Loopback (localhost / 127.0.0.1)

**How it works:** Standard TCP sockets bound to 127.0.0.1. Goes through the full TCP/IP network stack but never hits a physical NIC — the kernel recognizes the loopback address and routes packets directly back to the receive path.

```
Client ──► TCP stack ──► loopback interface ──► TCP stack ──► Server
           (no NIC, no wire, but still checksums and TCP state machine)
```

**Characteristics:**
- Full TCP overhead (connection state, congestion control, checksums) but no actual network latency
- ~0.1ms overhead vs UDS for typical request/response
- Multiple concurrent connections, standard HTTP
- Works identically in dev and prod
- Easy to debug with standard tools (curl, tcpdump, etc.)

**Good for:** When simplicity outweighs micro-optimization. The difference vs UDS is microseconds.

## 4.5 Shared Memory (`mmap` / `shm_open`)

**How it works:** Multiple processes map the same physical memory pages into their address spaces. Writes by one process are immediately visible to the other — zero-copy. (Same COW mechanism from section 2, but intentionally shared rather than copy-on-write.)

**Syscalls:** `shm_open()`, `mmap()`, `ftruncate()`

```
Process A                   Process B
  virtual addr 0x7f... ──┐   ┌── virtual addr 0x3a...
                         ▼   ▼
                    [Physical Memory Pages]
```

**Characteristics:**
- Zero-copy — fastest possible data transfer
- No syscalls for actual data exchange (just memory reads/writes)
- Requires explicit synchronization (mutex, semaphore, futex) to avoid races
- No built-in message passing — you design the protocol (ring buffers, slots, etc.)
- Complex to get right, especially across languages with different memory models

**Good for:** Extremely high throughput scenarios (video frames, large data buffers). Overkill for HTTP request/response patterns.

### `/dev/shm` — the Linux backing for shared memory

On Linux, `shm_open("my_buffer", ...)` creates a file at `/dev/shm/my_buffer` (see section 1's virtual filesystems). This is a `tmpfs` (RAM-backed filesystem) — no disk I/O, just memory with a filesystem interface. In Kubernetes, containers in the same pod can share it:

```yaml
volumes:
  - name: shared-mem
    emptyDir:
      medium: Memory   # mounted as tmpfs, backed by RAM
containers:
  - name: app
    volumeMounts:
      - name: shared-mem
        mountPath: /dev/shm
  - name: sidecar
    volumeMounts:
      - name: shared-mem
        mountPath: /dev/shm
```

**When /dev/shm makes sense:**
- One process produces large pre-computed data (search index, config blob) and writes it to `/dev/shm/cache.bin`
- Other process mmaps it read-only — always current, no requests needed
- NOT for request/response patterns — serialization cost dwarfs the copy savings at typical payload sizes (1-100KB)

## 4.6 Memory-Mapped Files

**How it works:** Similar to shared memory but backed by a persistent file. Multiple processes `mmap()` the same file and see each other's writes. The OS handles page faults and syncing to disk.

**Characteristics:**
- Persistent (survives process restart)
- Same zero-copy benefits as shared memory
- File acts as both the data and the coordination point
- Less common for request/response, more for shared state/config

**Good for:** Shared configuration, large lookup tables multiple processes need.

## 4.7 Message Queues (POSIX / System V)

**How it works:** Kernel-managed queue. Processes send discrete messages with types/priorities. The kernel handles buffering and ordering.

**Syscalls:** `mq_open()`, `mq_send()`, `mq_receive()` (POSIX)

**Characteristics:**
- Built-in message framing (you send messages, not byte streams)
- Priority-based delivery
- Persistence (messages survive sender crash until consumed)
- Size limits per message and per queue
- Less commonly used in modern architectures

**Good for:** Async work dispatch, priority-based processing. Rarely the right choice for HTTP-like request/response.

## 4.8 Eventfd / Signalfd (Linux-specific)

**How it works:** Lightweight kernel objects for signaling between processes. Eventfd is a counter that can be waited on; signalfd turns signals into readable file descriptors.

**Characteristics:**
- Not for data transfer — purely for signaling/wakeup
- Often paired with shared memory (shm for data, eventfd for "data is ready")
- Very low overhead for the notification itself

**Good for:** Wakeup mechanism alongside shared memory.

## IPC Comparison Table

| Mechanism | Latency | Concurrency | Framing | Complexity |
|-----------|---------|-------------|---------|------------|
| STDIO (pipes) | ~lowest | Serial (needs mux) | DIY | Low |
| Named pipes | ~lowest | Serial | DIY | Low |
| UDS | Very low | Native (multi-conn) | HTTP works | Low-Medium |
| TCP loopback | Low (+~0.1ms) | Native | HTTP works | Lowest |
| Shared memory | Zero-copy | Needs sync | DIY | High |
| Message queues | Medium | Built-in | Built-in | Medium |

---

# 5. The Socket API

Unix domain sockets (section 4.3) and TCP sockets (section 4.4) share the same API. This section explains that API in detail.

## Socket Creation

```c
int fd = socket(AF_INET, SOCK_STREAM, 0);
//              ^domain   ^type        ^protocol
```

| Parameter | Options | Meaning |
|-----------|---------|---------|
| Domain | `AF_INET` (IPv4), `AF_INET6` (IPv6), `AF_UNIX` (UDS) | Address family |
| Type | `SOCK_STREAM` (TCP/stream), `SOCK_DGRAM` (UDP/datagram), `SOCK_SEQPACKET` | Delivery semantics |
| Protocol | Usually 0 (auto) | Specific protocol within the family |

At this point you have an fd, but it's not bound to an address or connected to anything.

## Server Side: bind → listen → accept

```c
bind(fd, {addr: "0.0.0.0", port: 8080}, ...);  // Claim an address
listen(fd, 128);                                 // Mark as passive, set backlog
int client_fd = accept(fd, &client_addr, ...);   // Block until connection arrives
```

**What the kernel does at each step:**

- **`bind()`** — Associates the socket with a local address. For TCP, this reserves the IP:port. For UDS, this creates the filesystem path.

- **`listen()`** — Moves the socket into LISTEN state. The kernel creates two queues:
  - **SYN queue** (incomplete connections, TCP only) — received SYN, sent SYN-ACK, waiting for ACK
  - **Accept queue** (complete connections) — handshake done, waiting for `accept()`
  - The backlog parameter (128) controls the accept queue size

- **`accept()`** — Pops the next completed connection from the accept queue. Returns a **new fd** representing that specific connection. The original fd stays listening.

```
listen_fd (fd 3): always in LISTEN state, never carries data
                  ↓ accept()
client_fd (fd 4): ESTABLISHED, carries data for one connection
client_fd (fd 5): ESTABLISHED, carries data for another connection
```

Each connection has one fd on each side:

```
Server process          Kernel             Client process
  fd 4 ◄────────► [socket buffer pair] ◄────────► fd 3
```

## Client Side: connect

```c
int fd = socket(AF_INET, SOCK_STREAM, 0);
connect(fd, {addr: "1.2.3.4", port: 8080}, ...);
```

For TCP, the kernel:
1. Picks an ephemeral source port (e.g., 49152)
2. Sends SYN → waits for SYN-ACK → sends ACK (three-way handshake)
3. `connect()` returns — fd is now ESTABLISHED

For UDS, the kernel:
1. Immediately places the connection in the server's accept queue
2. `connect()` returns — no handshake, one syscall round-trip

## Data Transfer: read/write

```c
write(fd, "GET / HTTP/1.1\r\n...", len);   // or send()
read(fd, buffer, sizeof(buffer));           // or recv()
```

Each connected socket has **two kernel buffers**:

```
Process A                    Kernel                     Process B
          ┌─────────────────────────────────────────┐
write() ──► [Send buffer]  ──────────►  [Recv buffer] ──► read()
          └─────────────────────────────────────────┘
          ┌─────────────────────────────────────────┐
read() ◄── [Recv buffer]  ◄──────────  [Send buffer] ◄── write()
          └─────────────────────────────────────────┘
```

- **Send buffer** (~128KB default): `write()` copies data here and returns immediately. For TCP, the kernel handles transmission, retransmission, and windowing. For UDS, data appears directly in the peer's recv buffer.
- **Recv buffer** (~128KB default): Kernel places arrived data here. `read()` copies from it.
- If send buffer is full → `write()` blocks (or returns EAGAIN in non-blocking mode)
- If recv buffer is empty → `read()` blocks (or returns EAGAIN)

## Close & Connection Teardown

```c
close(fd);  // or shutdown(fd, SHUT_RDWR) for half-close
```

For TCP: triggers FIN sequence. Kernel keeps the socket in TIME_WAIT for 2×MSL (~60s) to handle stray packets.

For UDS: immediate cleanup, no TIME_WAIT.

---

# 6. The TCP/IP Network Stack

What happens inside the kernel when data flows over TCP — and why UDS is faster.

## Packet Path (outbound)

When you call `write(fd, data, len)` on a TCP socket:

```
Application:  write(fd, "hello", 5)
                    │
                    ▼
Socket layer: Copy to send buffer. Is there space? If not, block.
                    │
                    ▼
TCP layer:    Segment the data. Add TCP header (src port, dst port,
              seq number, ack number, window size, checksum).
              Manage retransmission timer.
                    │
                    ▼
IP layer:     Add IP header (src IP, dst IP, TTL, protocol=TCP).
              Route lookup — which interface + next-hop?
                    │
                    ▼
Netfilter:    iptables/nftables rules (OUTPUT chain).
              NAT, filtering, mangling.
                    │
                    ▼
Device layer: Add Ethernet frame (src MAC, dst MAC via ARP cache).
              Queue to NIC's TX ring buffer.
                    │
                    ▼
NIC:          DMA reads from ring buffer, puts on wire.
```

**For loopback (127.0.0.1):** Skips NIC/Ethernet entirely. At the IP layer, kernel recognizes loopback and routes directly to the receive path. Still goes through TCP state machine (checksums, windowing, etc.).

**For UDS:** Skips everything below the socket layer. `write()` copies to buffer, data appears in peer's recv buffer. No headers, no routing, no checksums.

## TCP vs UDS: What the Kernel Actually Does

```
TCP (even loopback):
  write() → socket buffer → TCP segment → IP route → netfilter → loopback →
  netfilter → IP reassemble → TCP reassemble → socket buffer → read()

UDS:
  write() → socket buffer → read()
```

| Operation | TCP loopback | UDS |
|-----------|-------------|-----|
| Memory copies | 2+ (user→kernel→user, plus internal copies) | 1-2 (user→kernel→user) |
| Headers added | TCP (20B) + IP (20B) | None |
| Checksum | Computed and verified | None |
| Routing lookup | Yes (trivial for loopback, but still executes) | No |
| Netfilter traversal | Yes (iptables rules evaluated) | No |
| Connection state machine | Full TCP FSM | Simplified |
| Congestion control | Active (though loopback never drops) | None needed |

## TCP Three-Way Handshake

```
Client                         Server
  │                              │  (listening, accept queue empty)
  │──── SYN (seq=x) ────────────►│  → SYN queue (half-open)
  │                              │
  │◄─── SYN-ACK (seq=y,ack=x+1)  │
  │                              │
  │──── ACK (ack=y+1) ──────────►│  → moved to accept queue
  │                              │
  │    ESTABLISHED               │  accept() returns new fd
```

UDS skips all of this — `connect()` immediately places the connection in the accept queue.

## TCP Socket States

```
LISTEN      → waiting for connections (server)
SYN_SENT    → sent SYN, waiting for SYN-ACK (client connecting)
SYN_RECV    → received SYN, sent SYN-ACK, waiting for ACK (in SYN queue)
ESTABLISHED → connected, data flowing
FIN_WAIT_1  → sent FIN, waiting for ACK
FIN_WAIT_2  → FIN ACK'd, waiting for peer's FIN
TIME_WAIT   → fully closed, waiting 2×MSL (~60s) for stray packets
CLOSE_WAIT  → received FIN, haven't sent ours yet (application hasn't called close())
LAST_ACK    → sent FIN, waiting for final ACK
CLOSED      → done
```

**TIME_WAIT** is the most operationally relevant:
- Accumulates on the side that initiates close (usually the server for HTTP/1.0, client for HTTP/1.1+)
- Each TIME_WAIT socket holds an ephemeral port for 60s
- High-traffic servers can exhaust ephemeral ports → SO_REUSEADDR + connection pooling

---

# 7. Socket Addressing

## 127.0.0.1 (loopback)

```c
bind(fd, "127.0.0.1:8080", ...);
```

- Only accepts connections **from the same machine**
- Packets never leave the network stack — no NIC, no wire
- External machines cannot reach this, even if firewalls are wide open
- The entire `127.0.0.0/8` range is loopback (127.0.0.2 also works, rarely used)

## 0.0.0.0 (INADDR_ANY)

```c
bind(fd, "0.0.0.0:8080", ...);
```

- Accepts connections on **all interfaces** — loopback, eth0, wlan0, docker0, etc.
- Kernel matches any incoming packet destined for port 8080 regardless of which IP it was addressed to
- This is what you use when you want external access

## :: (IPv6 any)

```c
bind(fd, ":::8080", ...);
```

- IPv6 equivalent of 0.0.0.0
- On Linux with dual-stack (default): also accepts IPv4 connections (mapped as `::ffff:x.x.x.x`)
- To disable dual-stack: `setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, 1)`

## Specific interface IP

```c
bind(fd, "192.168.1.50:8080", ...);
```

- Only accepts connections arriving on the interface with that IP
- Use case: machine with multiple NICs, you want the service only on the internal network

## localhost (the name)

- DNS resolves it — typically to `127.0.0.1` (and `::1` for IPv6)
- Defined in `/etc/hosts`, not a kernel concept
- Some systems resolve to `::1` first → your server must listen on IPv6 loopback too, or connections fail
- **Best practice for servers:** bind to `127.0.0.1` explicitly, not `localhost`, to avoid ambiguity

## Connection Matrix

```
Client connects to:        Server bound to:         Result:
────────────────────────────────────────────────────────────
127.0.0.1:8080             127.0.0.1:8080          ✓ works
127.0.0.1:8080             0.0.0.0:8080            ✓ works (any includes loopback)
192.168.1.50:8080          127.0.0.1:8080          ✗ refused (wrong interface)
192.168.1.50:8080          0.0.0.0:8080            ✓ works
192.168.1.50:8080          192.168.1.50:8080       ✓ works
external:8080              127.0.0.1:8080          ✗ refused
external:8080              0.0.0.0:8080            ✓ works (if firewall allows)
```

## Ephemeral Ports

When a client calls `connect()` without `bind()`ing first, the kernel picks a **source port** from the ephemeral range:

```bash
cat /proc/sys/net/ipv4/ip_local_port_range
# 32768  60999  (default: 28,231 ports available)
```

- Each TCP connection is identified by the 4-tuple: (src_ip, src_port, dst_ip, dst_port)
- Multiple connections to the same server use different ephemeral ports
- If you exhaust ephemeral ports → EADDRNOTAVAIL (too many connections to one destination)

---

# 8. Socket Options

## Port Binding: SO_REUSEADDR

```c
setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
```

**What it does:**
- Allows binding to a port that's in `TIME_WAIT` state (from a recently closed connection)
- Allows binding to a specific IP when another socket is bound to 0.0.0.0 on the same port (and vice versa)

**What it does NOT do:**
- Does NOT allow two sockets bound to the exact same address+port simultaneously

**Why you almost always want it:**
- Without it, restarting a server fails for ~60s (TIME_WAIT duration) because the old socket's port is "in use"
- Every production server sets this

```
Without SO_REUSEADDR:
  Server crashes → port in TIME_WAIT for 60s → restart fails with EADDRINUSE

With SO_REUSEADDR:
  Server crashes → restart immediately binds the port → works
```

## Port Sharing: SO_REUSEPORT

```c
setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
```

**What it does:**
- Multiple sockets CAN bind to the **exact same address+port** simultaneously
- Kernel distributes incoming connections across all listening sockets (load balancing)
- Each socket must set SO_REUSEPORT and must be owned by the same UID (security)

**The kernel's load balancing:**
```
                          ┌── accept() → Worker process 1 (fd on port 8080)
Incoming connection ──────┼── accept() → Worker process 2 (fd on port 8080)
   to port 8080           ├── accept() → Worker process 3 (fd on port 8080)
                          └── accept() → Worker process 4 (fd on port 8080)
```

**Use cases:**
- Multi-process servers without a parent distributing connections (no thundering herd)
- Zero-downtime restarts: new process binds same port, old process drains and exits
- Per-CPU socket binding for NUMA-aware workloads

**How Go/Node use it:**
```go
// Go: with net.ListenConfig
lc := net.ListenConfig{
    Control: func(network, address string, c syscall.RawConn) error {
        return c.Control(func(fd uintptr) {
            syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEPORT, 1)
        })
    },
}
listener, _ := lc.Listen(ctx, "tcp", ":8080")
```

```js
// Node: cluster module does this internally
const cluster = require('cluster');
if (cluster.isPrimary) {
    for (let i = 0; i < 4; i++) cluster.fork();
} else {
    http.createServer(handler).listen(8080);
    // Each worker gets SO_REUSEPORT (on Linux with cluster scheduling)
}
```

## SO_REUSEADDR vs SO_REUSEPORT

| | SO_REUSEADDR | SO_REUSEPORT |
|---|---|---|
| Purpose | Avoid TIME_WAIT conflicts | True multi-listener load balancing |
| Same addr+port? | No (just overlapping/TIME_WAIT) | Yes, genuinely |
| Load balancing | No | Kernel distributes connections |
| Security | Any user | Must be same UID |
| Set by default? | Should be (most frameworks do) | Opt-in |

## TCP_NODELAY (disable Nagle's algorithm)

```c
setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
```

- **Nagle's algorithm** (default ON): buffers small writes and sends them together to reduce packet count
- With Nagle on: write("H"), write("i") → kernel waits, sends "Hi" in one packet
- With Nagle off: each write() sends immediately, even 1 byte
- **Always set for request/response protocols** (HTTP, RPC) — Nagle adds latency waiting to batch
- Not relevant for UDS (UDS has no Nagle)

```
Without TCP_NODELAY (Nagle on):
  write("GET / HTTP/1.1\r\n")  → kernel: "small, let me wait for more..."
  write("Host: example.com\r\n") → kernel: "ok still buffering..."
  write("\r\n") → kernel: "200ms passed, fine, sending all at once"
  Result: one packet but 200ms delay

With TCP_NODELAY:
  write("GET / HTTP/1.1\r\n")  → sent immediately
  Result: possibly more packets, but no delay
```

## SO_KEEPALIVE

```c
setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof(one));
```

- Kernel sends periodic probes on idle TCP connections
- Detects dead peers (crashed without sending FIN)
- Default timing: 2hrs idle → probe every 75s × 9 retries (configurable per-socket on Linux 2.4+)

```c
setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &idle_secs, ...);   // time before first probe
setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl_secs, ...); // time between probes
setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &count, ...);        // probes before declaring dead
```

## SO_LINGER

```c
struct linger lg = { .l_onoff = 1, .l_linger = 5 };
setsockopt(fd, SOL_SOCKET, SO_LINGER, &lg, sizeof(lg));
```

- Controls what `close()` does with unsent data in the buffer
- Default (linger off): `close()` returns immediately, kernel sends remaining data in background
- Linger on, timeout > 0: `close()` blocks until data is sent OR timeout expires (then RST)
- Linger on, timeout = 0: `close()` sends RST immediately, discards unsent data (hard close, skips TIME_WAIT)

## SO_RCVBUF / SO_SNDBUF

```c
int size = 1024 * 1024;  // 1MB
setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, sizeof(size));
setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, sizeof(size));
```

- Set kernel buffer sizes for this socket (works for both TCP and UDS)
- Kernel actually allocates 2× what you request (internal bookkeeping)
- Larger buffers → higher throughput for bulk transfers, more memory per connection
- Larger buffers reduce syscall frequency (fewer read/write calls needed)

## TCP_FASTOPEN

```c
// Server side
setsockopt(fd, IPPROTO_TCP, TCP_FASTOPEN, &queue_len, sizeof(queue_len));

// Client side: send data WITH the SYN
sendto(fd, data, len, MSG_FASTOPEN, &addr, sizeof(addr));
```

- Sends data in the SYN packet (saves one round-trip on repeat connections)
- Client must have connected before (gets a cookie on first connect)
- Saves 1 RTT on subsequent connections — matters for WAN, irrelevant for localhost/UDS

## Kernel Buffer Tuning

```bash
# TCP buffer sizes (viewable via /proc — see section 1)
cat /proc/sys/net/core/rmem_default    # default recv buffer (212992)
cat /proc/sys/net/core/wmem_default    # default send buffer (212992)
cat /proc/sys/net/core/rmem_max        # max recv buffer
cat /proc/sys/net/core/wmem_max        # max send buffer

# UDS buffer (uses same rmem/wmem defaults)
# UDS also respects SO_SNDBUF/SO_RCVBUF per-socket

# Pipe buffer (STDIO)
cat /proc/sys/fs/pipe-max-size         # max (typically 1MB)
# Default per-pipe: 64KB (16 pages × 4KB)
```

---

# 9. I/O Multiplexing & Async I/O

A server with 1000 connections has 1000 fds. How to know which ones have data ready? (Section 1 explained the wait-queue mechanism — this section covers the APIs that use it.)

## select() — the original (1983)

```c
fd_set read_fds;
FD_SET(fd4, &read_fds);
FD_SET(fd5, &read_fds);
select(max_fd + 1, &read_fds, NULL, NULL, timeout);
// Kernel scans ALL fds in the set, returns which are ready
```

O(n) scan every time. Limited to 1024 fds (FD_SETSIZE).

## poll() — removes the fd limit (1997)

```c
struct pollfd fds[] = {{fd4, POLLIN}, {fd5, POLLIN}};
poll(fds, 2, timeout);
```

Still O(n) — kernel scans all entries every call. But no fd count limit.

## epoll() — the Linux solution (2002)

```c
int epfd = epoll_create1(0);
epoll_ctl(epfd, EPOLL_CTL_ADD, fd4, &event);  // Register once
epoll_ctl(epfd, EPOLL_CTL_ADD, fd5, &event);

// Wait — kernel only returns READY fds
int n = epoll_wait(epfd, events, max_events, timeout);
```

- Kernel maintains a ready-list internally
- When data arrives on a socket, kernel adds it to the ready-list (via the wait-queue callback from section 1)
- `epoll_wait` just returns whatever is already on the ready-list — O(1)
- This is what Node.js (libuv), Go (netpoll), and nginx use under the hood
- Works with both TCP sockets and UDS

```
Node.js event loop:
  libuv → epoll_wait() → "fd 4 and fd 7 are readable" → fire callbacks

Go runtime:
  netpoll → epoll_wait() → wake goroutines blocked on those sockets
```

## macOS equivalent: kqueue

macOS doesn't have epoll. It uses `kqueue`/`kevent` — same O(1) concept, different API. kqueue is actually more capable than epoll (natively supports files, signals, processes, timers), but still readiness-based.

## io_uring — the next generation (2019, Linux 5.1)

io_uring is a fundamentally different model. All previous mechanisms are **readiness-based** — they tell you *when* an fd is ready, then you issue the actual read/write syscall. io_uring is **completion-based** — you tell the kernel *what I/O to perform*, and it tells you *when it's done*.

This solves the "regular files are always ready" limitation from section 1 — io_uring can do truly async file I/O.

| Aspect | epoll | io_uring |
|--------|-------|----------|
| Model | Readiness ("fd is readable now") | Completion ("your read finished, here's the data") |
| Syscalls needed | epoll_wait + read/write per operation | Zero in SQPOLL mode |
| File I/O | Not supported (regular files always report "ready") | Fully async |
| Operations | Socket readiness only | 60+ ops: read, write, send, recv, accept, connect, fsync, openat, close, statx... |
| Kernel-user interface | Syscalls | Shared memory ring buffers |

### How it works: Two ring buffers in shared memory

```
    Userspace                          Kernel
┌──────────────────┐              ┌─────────────────┐
│ Submission Queue │    mmap'd    │                 │
│   Ring (SQR)     │◄────shared──►│  Kernel reads   │
│                  │   memory     │  SQEs from here │
│  [SQE][SQE][SQE] │              │                 │
└──────────────────┘              └─────────────────┘

┌──────────────────┐              ┌─────────────────┐
│ Completion Queue │    mmap'd    │                 │
│   Ring (CQR)     │◄────shared───►  Kernel writes  │
│                  │   memory     │  CQEs to here   │
│  [CQE][CQE][CQE] │              │                 │
└──────────────────┘              └─────────────────┘
```

**Submission Queue Entry (SQE):** 64-byte struct — opcode, fd, buffer address, offset, length, user_data for correlation.

**Completion Queue Entry (CQE):** 16-byte struct — user_data (to correlate back), result (bytes read, or error).

**The flow:**
1. App writes SQEs into submission ring (just memory writes — no syscall)
2. App updates SQ tail pointer
3. Kernel processes SQEs, performs the I/O
4. Kernel writes CQEs into completion ring
5. App reads CQEs by checking CQ head vs tail (no syscall)

### Key modes

- **Default:** `io_uring_enter()` syscall needed to submit/wait — still fewer syscalls than epoll (one call batches many ops)
- **SQPOLL:** Kernel spawns a polling thread that watches the SQ. Achieves **zero-syscall I/O** — userspace just writes to memory and reads from memory
- **IOPOLL:** Kernel busy-polls for completions instead of interrupts. Best for NVMe/high-IOPS storage

### Advanced features

- **Linked SQEs:** Chain operations with ordering (read → write as atomic sequence)
- **Fixed files/buffers:** Pre-register fds and buffers to skip per-op kernel lookups
- **Multishot operations:** One SQE produces multiple CQEs (e.g., multishot accept — one submission handles many incoming connections)

### Performance vs epoll

- **High connection count (10K+):** 20-40% throughput improvement due to batching and syscall reduction
- **Storage I/O:** Can saturate modern NVMe drives (millions of IOPS) where older interfaces cannot
- **Low connection count:** Marginal difference — epoll is already efficient
- **SQPOLL latency:** Sub-microsecond submission (just a memory write vs syscall overhead)

### Adoption

| Runtime | Status |
|---------|--------|
| **Node.js** | Not adopted. libuv still uses epoll. Experimental branch for file I/O not merged (security concerns). |
| **Go** | Not adopted. netpoller uses epoll. Third-party libraries exist (e.g., `iceber/iouring-go`). |
| **Bun** | Uses io_uring for both file and network I/O on Linux |
| **Rust/Tokio** | `tokio-uring` crate provides io_uring-backed async runtime |
| **ScyllaDB/Seastar** | io_uring for storage |

**Why mainstream runtimes haven't switched:** Go's goroutine model already amortizes syscall cost well. Node's epoll-based approach is adequate for network I/O. io_uring has also had multiple security CVEs — some cloud environments (Google) disable it entirely.

### The evolution

```
1983: select()     — O(n) scan, 1024 fd limit
1997: poll()       — O(n) scan, no fd limit
2002: epoll()      — O(1) readiness notification, still need read/write syscalls
2019: io_uring     — zero-syscall completion-based async I/O via shared memory
```

---

# 10. Debugging & Observability

```bash
# All listening sockets with process info
ss -tlnp

# All connections to a specific port
ss -tan dst :8080

# UDS sockets
ss -xlnp

# Socket buffer sizes for a connection
ss -tm   # shows Send-Q, Recv-Q, and memory info

# See socket options on a running process
strace -e setsockopt -p <pid>

# Count connections per state
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn

# Check what's bound to a port
lsof -i :8080

# Watch connection rate
watch -n1 'ss -s'

# See all socket states
ss -tan

# Count connections in TIME_WAIT
ss -tan state time-wait | wc -l
```

---

# Part II: Case Study

---

# 11. Case Study: Svelte SSR + Go Backend Architecture

Applying the fundamentals above to a real architecture: a SvelteKit SSR frontend with a Go API backend, deployed as a single unit.

## The Problem

- SvelteKit handles server-side rendering (SSR) and client navigation
- Go provides the API backend (business logic, data access)
- Both run in the same pod — communication should be as fast as possible
- Browser only sees one origin (single port exposed)

## Architecture Decision: Go as Front Door

After first page load + hydration, ~80% of requests are API calls, ~10% are SSR renders, ~10% are static assets. Go is better suited as the front door:

- Goroutines handle thousands of concurrent connections efficiently
- Built for middleware concerns (auth, rate limiting, observability)
- API calls (the majority) hit Go directly — no extra hop
- Static files served efficiently (or offloaded to CDN)
- SSR (the minority path) gets proxied to SvelteKit

## Data Flow

```
Browser ──HTTP──► Go (:8080, bound to 0.0.0.0)
                   │
                   ├─ /api/*     → Go handles directly (no proxy)
                   ├─ /static/*  → Go serves files (or CDN)
                   └─ /* pages   → reverse proxy to SvelteKit over UDS
                                    │
                                    └─ load() ──fetch via UDS──► Go (for data)
```

**Three request types:**
1. **API calls from browser** → Go handles directly. Fast path, no intermediary.
2. **Page renders (SSR)** → Go proxies to SvelteKit via UDS. SvelteKit runs `load` functions, renders HTML, returns to Go, Go responds to browser.
3. **SvelteKit load functions → Go** → SvelteKit fetches data from Go over UDS (or localhost). This looks circular but isn't — it's two processes talking over kernel buffers.

## IPC Choice: Unix Domain Sockets

From section 4's comparison, UDS is the best fit:
- Concurrent connections needed (multiple SSR renders in parallel)
- HTTP semantics work natively (Go's `httputil.ReverseProxy` supports UDS)
- No TCP overhead (no handshake, no TIME_WAIT, no checksums — section 6)
- Single filesystem path, no port allocation needed

## Socket Configuration

Applying section 8 options to this architecture:

```
Go server (front door, accepts browser connections):
  Bind:           0.0.0.0:8080   (external access — section 7)
  SO_REUSEADDR  = 1              (graceful restarts, avoid TIME_WAIT bind failures)
  TCP_NODELAY   = 1              (HTTP request/response, no Nagle delay)
  SO_KEEPALIVE  = 1              (detect dead browser connections)

Go → SvelteKit (UDS, reverse proxy for SSR):
  Socket path:    /tmp/svelte.sock
  No TCP options  (UDS has no Nagle, no TIME_WAIT, no handshake)
  SO_RCVBUF/SO_SNDBUF increased if SSR HTML payloads are large

SvelteKit → Go (UDS, load function data fetching):
  Same UDS path or separate one
  Connection pooling (reuse connections across load() calls)
```

## Node.js Undici Dispatchers

SvelteKit's `load` functions need to call Go for data. Node's built-in `fetch` (powered by undici) supports custom dispatchers that control the transport layer:

```js
import { Agent } from 'undici';

// Route all requests to Go through UDS
const goBackend = new Agent({
  connect: { socketPath: '/tmp/go.sock' }
});

// In a SvelteKit load function:
export async function load() {
  // URL host is ignored — connection goes through the socket
  const res = await fetch('http://go/api/users', {
    dispatcher: goBackend
  });
  return { users: await res.json() };
}
```

**Dispatcher types:**
```js
import { Agent, Client, Pool } from 'undici';

// Connection pooling (multiple connections reused)
const pooled = new Agent({ connections: 10, keepAliveTimeout: 30_000 });

// HTTP pipelining (multiple in-flight requests per connection)
const pipelined = new Client('http://localhost:8080', { pipelining: 6 });

// Swap transport without changing application code
const go = process.env.NODE_ENV === 'production'
  ? new Agent({ connect: { socketPath: '/tmp/go.sock' } })
  : new Agent({ connect: { host: 'localhost', port: 8080 } });
```

## Why Not STDIO?

From section 4.1: pipes are serial (single stream, no concurrency). Multiple concurrent SSR renders would require request-ID multiplexing over a single pipe — more complex than just using UDS which gives concurrent connections natively.

## Why Not Shared Memory?

From section 4.5: JSON serialization/deserialization dominates at typical API payload sizes (1-100KB). The zero-copy benefit of shared memory is irrelevant — you'd still need to serialize. However, if Go pre-computes large read-only data (product catalog, config), `/dev/shm` could work for that specific case alongside UDS for request/response.

## Why Not TCP Loopback?

It would work fine — the ~0.1ms overhead vs UDS is negligible. The real benefits of UDS here:
- No port allocation (avoids ephemeral port exhaustion under high load — section 7)
- No TIME_WAIT accumulation (section 6)
- Filesystem permissions for access control
- Slightly lower kernel overhead (section 6's comparison table)

TCP loopback is a valid alternative if simplicity is preferred over optimization.
