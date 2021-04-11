---
layout: page
title: Data
---

`Data` is an in-built `struct` that allows to allocate a certain amount of memory to be used and accessed as an array.

``` 
params: 
    numOfPhasors {1, 1, 100}

struct Phasor: 
    phase

init:
    data  = Data(10)                   # 10 float elements: Data() defaults to Data[float]()
    
    data2 = Data[float](10)            # 10 float elements
    
    data3 = Data[int](10)              # 10 int elements
    
    data4 = Data[Data[float]](10)      # 10 Data[float] elements
    loop data4:                        # loop around all elements and initialize Datas
        _ = Data(10)  
    
    data5 = Data[Phasor](numOfPhasors) # dynamic count according to value of param 'numOfPhasors'
    #[ 
    Note that there is no need of looping around data5 to initialize all entries explicitly by
    calling 'Phasor()', Omni will detect all non-initialized entries and automatically initialize
    them at the end of the init block. However, if one needs to initialize the entries with a
    value that is not the default 'Phasor()', perhaps 'Phasor(10)', this must be done explicitly 
    ]#

    data6 = Data(10, 2)                # 20 total elements: 10 float elements per channel

    print data[0]                      # single channel access

    print data6[0, 0]                  # multichannel access: [chan, index]

```

`Data` can store any user defined `struct`. If the entries are not explicitly initialized, *Omni* will do it for you at the end of the `init` block using the default constructor of the specific `struct`. Furthermore, if you try to access a non-initialized field, *Omni* will initialize it at the moment of access:

```
struct Something:
    data Data

init:
    a = Data[Something](10)
    
    #Will initialize a[1] to Something()
    print a[1].data[0]

    #Will initialize a[9] to Something(). a[1000] is out of bounds, so it returns the last entry, which is a[9]
    #data[1000] is also out bounds, so it will return 0 
    print a[1000].data[1000]

    #a[1] is already initialized, will not re-initialize it and print warning
    a[1] = Something()
```

<br>

## [Next: 08 - External memory: Buffer](08_buffer.md)