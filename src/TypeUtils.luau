--!strict

--[[
	Makes all read-only or write-only properties to be both writable and readable.
]]
export type function internal(ty: type)
	local opCount = 0
	const function incOpCount()
		assert(opCount <= 10000, "Type too complex: operation limit exceeded")
		opCount += 1
	end

	const function processType(t: type, depth: number)
		assert(depth <= 20, "Type too complex: recursion depth limit exceeded")

		const tTag = t.tag
		if tTag == "table" then
			-- props
			for keyType, rwType in t:properties() do
				incOpCount()
				t:setproperty(
					keyType,
					processType(rwType.read or rwType.write :: type, depth + 1)
				)
			end
			
			-- indexer
			const indexer = t:indexer()
			if indexer then
				incOpCount()
				t:setindexer(
					indexer.index,
					processType(indexer.readresult, depth + 1)
				)
			end
		elseif tTag == "union" then
			const components = t:components()
			for i, component in components do
				incOpCount()
				components[i] = processType(component, depth + 1)
			end

			return types.unionof(table.unpack(components))
		elseif tTag == "intersection" then
			const components = t:components()
			for i, component in components do
				incOpCount()
				components[i] = processType(component, depth + 1)
			end

			return types.intersectionof(table.unpack(components))
		end

		return t
	end

	return processType(ty, 0)
end

--[=[
--[[
	Cleanly merges two or more given tables into one, resolving conflicts by unionizing properties/indexers.
]]
type function f_mergebyunion(tyProxy: type)
	local parameters = tyProxy:parameters().head
	if not parameters then
		return types.unknown
	end
	
	const function checkTable(ty: type, argNum: number)
		local tag = ty.tag
		if tag == "table" then return end
		
		error(`mergetables<> can only be used with tables, got '{tag}' instead for argument #{argNum}`)
	end
	
	local firstTbl = parameters[1]
	if not firstTbl then
		return types.unknown
	end
	
	checkTable(firstTbl, 1)
	
	-- start iteration after the first index
	for i, tbl in next, parameters, 1 do
		checkTable(tbl, i)
		
		for keyType, rwType in tbl:properties() do
			local rType = rwType.read
			if rType then
				local existing = firstTbl:readproperty(keyType)
				
				firstTbl:setreadproperty(keyType, if existing
					then types.unionof(existing, rType)
					else rType
				)
			end
			
			local wType = rwType.write
			if wType then
				local existing = firstTbl:writeproperty(keyType) -- this GETS the write property, despite the confusing name
				
				firstTbl:setwriteproperty(keyType, if existing
					then types.unionof(existing, wType)
					else wType
				)
			end
		end
		
		-- Handle indexer
		-- Currently, different indexers for read/write are not implemented in Luau
		local indexer = tbl:readindexer()
		if not indexer then continue end
		
		local existing = firstTbl:readindexer()
		if existing then
			firstTbl:setindexer(
				types.unionof(existing.index, indexer.index),
				types.unionof(existing.result, indexer.result)
			)
		else
			firstTbl:setindexer(indexer.index, indexer.result)
		end
	end
	
	return firstTbl
end

export type mergebyunion<T...> = f_mergebyunion<(T...)->()>]=]

--[[
	Removes all nils from the given union type recursively (unions nested in tables).
]]
export type function requireddeep(ty: type)
	local opCount = 0
	const function incOpCount()
		if opCount > 10000 then
			error("Type too complex: operation limit exceeded")
		end		

		opCount += 1
	end

	const function processType(t: type, depth: number)
		if depth > 20 then
			error("Type too complex: recursion depth limit exceeded")
		end

		local tTag = t.tag
		if tTag == "table" then
			for keyType, rwType in t:properties() do
				incOpCount()
				
				t:setproperty(keyType, processType(rwType.read or rwType.write :: type, depth + 1))
			end
		elseif tTag == "union" then
			local components = t:components()
			for i = #components, 1, -1 do
				incOpCount()
				
				local component = components[i]
				if component:is("singleton") and component:value() == nil then
					table.remove(components, i)
				end
			end

			return types.unionof(table.unpack(components))
		end

		return t
	end

	return processType(ty, 0) or types.singleton(nil)
end

export type function childof(instance: type)
	local instanceTag = instance.tag
	if instanceTag ~= "extern" then
		error(`childof<type> expects an externtype, got {instanceTag} instead.`)
	end
	
	local properties = instance:properties()
	local children: {[type]: type} = {}
	
	for keyType, rwType in properties do
		-- The only property that is included in the dict is "Parent".
		-- Depending on your use case it might also be useful to include this.
		if keyType:value() == "Parent" then
			continue
		end
		
		children[keyType] = rwType.read
	end
	
	return types.newtable(children)
end

return nil