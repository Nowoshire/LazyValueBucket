--[[
	-- LuauTypeUtils --

	v0.1.1

	A collection of various type utilities for the New Luau Type Solver.

	This software is licensed under the MIT License:
		https://github.com/Nowoshire/LuauTypeUtils/blob/main/LICENSE

		MIT License

		Copyright (c) 2026 Nowoshire

		Permission is hereby granted, free of charge, to any person obtaining a copy
		of this software and associated documentation files (the "Software"), to deal
		in the Software without restriction, including without limitation the rights
		to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
		copies of the Software, and to permit persons to whom the Software is
		furnished to do so, subject to the following conditions:

		The above copyright notice and this permission notice shall be included in all
		copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
		IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
		FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
		AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
		LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
		OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
		SOFTWARE.
]]

--!strict

--[[
	Makes all read-only or write-only properties to be both writable and readable.
]]
type function fn_internal(ty: type)
	const function processType(t: type)
		const tTag = t.tag
		if tTag == "table" then
			-- props
			for keyType, rwType in t:properties() do
				t:setproperty(
					keyType,
					processType(rwType.read or rwType.write :: type)
				)
			end
			
			-- indexer
			const indexer = t:indexer()
			if indexer then
				t:setindexer(
					indexer.index,
					processType(indexer.readresult)
				)
			end
		elseif tTag == "union" then
			const components = t:components()
			for i, component in components do
				components[i] = processType(component)
			end

			return types.unionof(table.unpack(components))
		elseif tTag == "intersection" then
			const components = t:components()
			for i, component in components do
				components[i] = processType(component)
			end

			return types.intersectionof(table.unpack(components))
		end

		return t
	end

	return processType(ty)
end

export type internal<ty> = fn_internal<ty>

--[[
	Removes all nils from the given union type recursively (unions nested in tables).
]]
type function fn_requireddeep(ty: type)
	local opCount = 0
	const function incOpCount()
		if opCount > 10000 then
			error("Type too complex: operation limit exceeded")
		end		

		opCount += 1
	end

	const function processType(t: type)
		local tTag = t.tag
		if tTag == "table" then
			for keyType, rwType in t:properties() do
				incOpCount()
				
				t:setproperty(keyType, processType(rwType.read or rwType.write :: type))
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

	return processType(ty) or types.singleton(nil)
end

export type requireddeep<ty> = fn_requireddeep<ty>

--[[
	Returns a tabletype containing the Instance's child Instances.
]]
type function fn_childof(instance: type)
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

export type childof<instance> = fn_childof<instance>

return nil