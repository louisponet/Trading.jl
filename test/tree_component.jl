using TestItems

@testitem "interface" tags=[:treecomponent] begin
    using Trading.Overseer: test_abstractcomponent_interface
    using Trading: TreeComponent

    test_abstractcomponent_interface(TreeComponent)
end

@testitem "adding" tags=[:treecomponent] begin
    using Trading.Overseer: TestCompData, test_abstractcomponent_interface
    using Trading: TreeComponent
    
    c = TreeComponent{TestCompData}()
    vals = rand(1:100, 1000)

    for (i, v) in enumerate(vals)
        c[Entity(i)] = TestCompData(v)
    end
    
    for i in 1:100
        n = count(isequal(i), vals)

        list = c[TestCompData(i)]
        @test length(list) == n
    end
end

@testitem "removing" tags=[:treecomponent] begin
    using Trading.Overseer: TestCompData, test_abstractcomponent_interface
    using Trading: TreeComponent
    
    c = TreeComponent{TestCompData}()
    vals = rand(1:100, 1000)

    for (i, v) in enumerate(vals)
        c[Entity(i)] = TestCompData(v)
    end
    
    for i in 1:1000
        n = count(isequal(vals[i]), vals[i:end])
        
        v = pop!(c, Entity(i))
        @test v.p == vals[i]
        
        list = c[v[TestCompData]]
        if n == 1
            @test list === nothing
        else
            @test length(list) == n - 1
        end
    end
    @test isempty(c)
    @test isempty(c.tree)
end
    
@testitem "ceil/floor" tags=[:treecomponent] begin
    using Trading.Overseer: TestCompData, test_abstractcomponent_interface
    using Trading: TreeComponent
    c = TreeComponent{TestCompData}()
    vals = rand(1:100, 1000)

    sorted_vals = TestCompData.(unique(sort(vals)))

    for (i, v) in enumerate(vals)
        c[Entity(i)] = TestCompData(v)
    end

    v = ceil(c, sorted_vals[1])
    @test v.ptr[] == sorted_vals[1]
    cnt = 0
    while v !== nothing
        global v = ceil(c, TestCompData(v.p+1))
        global cnt += 1
    end
    @test cnt == length(sorted_vals)
    
    v = floor(c, sorted_vals[end])
    @test v.ptr[] == sorted_vals[end]
    cnt = 0
    while v !== nothing
        global v = floor(c, TestCompData(v.p-1))
        global cnt += 1
    end
    @test cnt == length(sorted_vals)
end

@testitem "inorder iteration" tags=[:treecomponent] begin
    using Trading.Overseer: TestCompData, test_abstractcomponent_interface
    using Trading: TreeComponent
    c = TreeComponent{TestCompData}()
    vals = rand(1:100, 1000)

    sorted_vals = TestCompData.(sort(unique(vals)))

    for (i, v) in enumerate(vals)
        c[Entity(i)] = TestCompData(v)
    end

    for (i, v) in enumerate(c.tree)
        @test sorted_vals[i] == v.ptr[]
    end
end
@testitem "maximum/minimum" tags=[:treecomponent] begin
    using Trading.Overseer: TestCompData, test_abstractcomponent_interface
    using Trading: TreeComponent
    c = TreeComponent{TestCompData}()
    vals = rand(1:100, 1000)

    sorted_vals = TestCompData.(sort(unique(vals)))

    for (i, v) in enumerate(vals)
        c[Entity(i)] = TestCompData(v)
    end

    maxid = findmax(vals)[2]
    minid = findmin(vals)[2]
    
    @test Entity(maximum(c)) == Entity(maxid)
    @test maximum(c).p == sorted_vals[end]
    
    @test Entity(minimum(c)) == Entity(minid)
    @test minimum(c).p == sorted_vals[1]
end
